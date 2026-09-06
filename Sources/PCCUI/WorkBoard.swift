import Foundation

/// The Work screen's action-side arithmetic — the priority queue, the
/// deadline horizon, and the per-row context the container tree shows
/// (issues #101, #103, #105).
///
/// Sits beside `WorkTree`, which owns the same screen's *totals*: that type
/// answers "how much time went where", this one answers "what should I do
/// next, and what needs attention". Both are pure `enum` namespaces with no
/// state, so the rules are testable without a view model or a live backend
/// (`WorkBoardTests`), the same seam `SchoolBoard` uses on the School side.
///
/// Everything here is derived from the flat lists `WorkViewModel` already
/// loads. Nothing invents a figure the model can't produce.
public enum WorkBoard {

    // MARK: - Work scope

    /// Whether a Task belongs to this screen at all: not Course work, either
    /// directly or through a Course-owned Project (ADR-0011). The same
    /// exclusion `WorkTree.build` applies, restated here because the queue is
    /// built from the flat Task list rather than walked out of the tree.
    public static func isWorkTask(_ task: PCCTask, projects: [Project]) -> Bool {
        SchoolBoard.courseID(for: task, projects: projects) == nil
    }

    // MARK: - Priority queue

    /// The Today card's list: the open work Tasks that matter now, ordered by
    /// Deadline proximity — which puts overdue ones first, since an overdue
    /// date is simply the earliest — with undated Tasks after every dated one
    /// and ties broken by title.
    ///
    /// That ordering is `SchoolBoard.areInProximityOrder`, the same rule the
    /// Deadlines screen and the School board already sort by, rather than a
    /// third competing notion of priority.
    ///
    /// Undated Tasks are included rather than filtered out. A strict "due
    /// today" reading would leave the card empty for an owner who doesn't
    /// date every Task, and an empty hero panel is worse than a slightly
    /// looser one; the proximity order already keeps them below everything
    /// with a real deadline.
    ///
    /// Deliberately not scoped by the screen's range stepper: "what should I
    /// work on right now" is about today no matter which week the panels
    /// below are reporting on.
    public static func priorityQueue(
        tasks: [PCCTask], projects: [Project], clients: [PCCClient], timeEntries: [TimeEntry],
        calendar: Calendar = .current, reference: Date = Date()
    ) -> [WorkPriorityTask] {
        let todaySeconds = secondsPerTaskToday(
            timeEntries, calendar: calendar, reference: reference)
        return tasks
            .filter { !$0.isComplete && isWorkTask($0, projects: projects) }
            .map { task in
                let project = task.projectID.flatMap { id in projects.first { $0.id == id } }
                let client = project?.clientID.flatMap { id in clients.first { $0.id == id } }
                return WorkPriorityTask(
                    task: task,
                    clientName: client?.name,
                    projectName: project?.name,
                    loggedTodaySeconds: todaySeconds[task.id] ?? 0
                )
            }
            .sorted {
                SchoolBoard.areInProximityOrder(
                    ($0.task.dueDate, $0.task.title), ($1.task.dueDate, $1.task.title))
            }
    }

    /// The one-line summary above the queue: how much has been logged today,
    /// how many work Tasks are still open, and how many of those are overdue.
    ///
    /// "Open" is the whole backlog rather than only today's slice — it's the
    /// figure the queue below is a window onto — while "overdue" and "due
    /// today" are the two counts that actually demand something today.
    public static func todaySummary(
        tasks: [PCCTask], projects: [Project], timeEntries: [TimeEntry],
        calendar: Calendar = .current, reference: Date = Date()
    ) -> WorkTodaySummary {
        let dayStart = calendar.startOfDay(for: reference)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let open = tasks.filter { !$0.isComplete && isWorkTask($0, projects: projects) }
        return WorkTodaySummary(
            loggedSeconds: loggedSecondsToday(
                timeEntries, calendar: calendar, reference: reference),
            openTasks: open.count,
            overdueTasks: open.filter { ($0.dueDate ?? .distantFuture) < dayStart }.count,
            dueTodayTasks: open.filter {
                guard let due = $0.dueDate else { return false }
                return due >= dayStart && due < dayEnd
            }.count
        )
    }

    /// Seconds logged on `reference`'s calendar day, bucketed by Task id —
    /// what each queue row's "so far today" figure reads. Entries logged
    /// straight against a Project or Client have no Task to key by and are
    /// skipped; they still count toward the day's grand total below.
    ///
    /// A running timer counts toward nothing until it's stopped
    /// (`CONTEXT.md`), so it's skipped here exactly as `WorkTree` skips it.
    private static func secondsPerTaskToday(
        _ timeEntries: [TimeEntry], calendar: Calendar, reference: Date
    ) -> [UUID: Double] {
        var totals: [UUID: Double] = [:]
        forEachEntryToday(timeEntries, calendar: calendar, reference: reference) { entry, seconds in
            guard let taskID = entry.taskID else { return }
            totals[taskID, default: 0] += seconds
        }
        return totals
    }

    /// Everything logged today across all four container kinds — the summary
    /// line's hours figure, which is a wider question than the per-Task one
    /// above ("where did my day go", not "how far into this Task am I").
    public static func loggedSecondsToday(
        _ timeEntries: [TimeEntry], calendar: Calendar = .current, reference: Date = Date()
    ) -> Double {
        var total = 0.0
        forEachEntryToday(timeEntries, calendar: calendar, reference: reference) { _, seconds in
            total += seconds
        }
        return total
    }

    /// The day-window walk both of the above share: completed entries whose
    /// `startDate` lands on `reference`'s calendar day, with their duration.
    private static func forEachEntryToday(
        _ timeEntries: [TimeEntry], calendar: Calendar, reference: Date,
        _ body: (TimeEntry, Double) -> Void
    ) {
        let dayStart = calendar.startOfDay(for: reference)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        for entry in timeEntries {
            guard let endDate = entry.endDate else { continue }
            guard entry.startDate >= dayStart, entry.startDate < dayEnd else { continue }
            body(entry, endDate.timeIntervalSince(entry.startDate))
        }
    }

    /// How a due date reads on a row: overdue, a clock time when it lands
    /// today, "Tomorrow", a weekday inside the coming week, and a date beyond
    /// that.
    ///
    /// Urgency rather than a bare date on purpose — "Due in 2h" tells the
    /// owner something "September 5" doesn't, on the one day that matters.
    public static func urgency(
        for dueDate: Date?, calendar: Calendar = .current, reference: Date = Date()
    ) -> WorkUrgency {
        guard let dueDate else { return .undated }
        let dayStart = calendar.startOfDay(for: reference)
        let dueDay = calendar.startOfDay(for: dueDate)
        let days = calendar.dateComponents([.day], from: dayStart, to: dueDay).day ?? 0
        // Measured in whole calendar days rather than elapsed hours: a Task
        // due at 9am is not "overdue" at 10am the same morning — it's still
        // today's work, and calling it late would flag most of a normal day.
        switch days {
        case ..<0: return .overdue(days: -days)
        case 0: return .today(dueDate)
        case 1: return .tomorrow
        case 2...6: return .thisWeek(dueDate)
        default: return .later(dueDate)
        }
    }

    // MARK: - Deadline horizon

    /// The Upcoming card: work-side Deadlines inside the next `horizonDays`,
    /// plus every overdue one regardless of how far back it sits, grouped by
    /// the day they fall on and ordered soonest first.
    ///
    /// Course Deadlines are dropped — a Course-owned Task, Project, or the
    /// Course itself belongs to the School dashboard, the same split the rest
    /// of this screen already makes. `DeadlineItem` carries only a kind and an
    /// id, so Course ownership is resolved by looking the id back up in the
    /// Tasks and Projects the screen has already loaded.
    ///
    /// Completed items are dropped too: a finished Task's Deadline is no
    /// longer something the week demands.
    public static func upcoming(
        deadlines: [DeadlineItem], tasks: [PCCTask], projects: [Project],
        horizonDays: Int = 7, calendar: Calendar = .current, reference: Date = Date()
    ) -> [WorkDeadlineGroup] {
        let dayStart = calendar.startOfDay(for: reference)
        let horizonEnd = calendar.date(byAdding: .day, value: horizonDays, to: dayStart) ?? dayStart

        let kept = deadlines.filter { item in
            guard item.isComplete != true else { return false }
            guard let dueDate = item.dueDate, dueDate < horizonEnd else { return false }
            switch item.kind {
            case .course:
                return false
            case .task:
                guard let task = tasks.first(where: { $0.id == item.id }) else { return false }
                return isWorkTask(task, projects: projects)
            case .project:
                guard let project = projects.first(where: { $0.id == item.id }) else { return false }
                return project.courseID == nil
            }
        }

        // Overdue items collapse into one leading group rather than one group
        // per past day: how late something is belongs on the row, while the
        // heading only has to say that it *is* late.
        let overdue = kept
            .filter { ($0.dueDate ?? .distantFuture) < dayStart }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        var groups: [WorkDeadlineGroup] = []
        if !overdue.isEmpty {
            groups.append(WorkDeadlineGroup(day: nil, isOverdue: true, items: overdue))
        }

        let upcoming = kept.filter { ($0.dueDate ?? .distantPast) >= dayStart }
        let byDay = Dictionary(grouping: upcoming) { calendar.startOfDay(for: $0.dueDate!) }
        for day in byDay.keys.sorted() {
            let items = (byDay[day] ?? []).sorted {
                SchoolBoard.areInProximityOrder(($0.dueDate, $0.title), ($1.dueDate, $1.title))
            }
            groups.append(WorkDeadlineGroup(day: day, isOverdue: false, items: items))
        }
        return groups
    }

    // MARK: - Tree row context

    /// The secondary line a Client or Project row shows under its name —
    /// how many Projects sit under it, how many Tasks are still open, and how
    /// many of those are overdue.
    ///
    /// Computed for Client and Project rows only. A Sprint or Task row gets
    /// `nil`: the tree still has to read as a tree, and a caption under every
    /// leaf would bury the structure the card exists to show.
    public static func rowContext(
        for kind: WorkNodeKind, projects: [Project], tasks: [PCCTask],
        calendar: Calendar = .current, reference: Date = Date()
    ) -> WorkRowContext? {
        let dayStart = calendar.startOfDay(for: reference)
        let scopedProjects: [Project]
        switch kind {
        case .client(let id):
            scopedProjects = projects.filter { $0.clientID == id && $0.courseID == nil }
        case .project(let id):
            scopedProjects = projects.filter { $0.id == id }
        case .unassigned:
            scopedProjects = projects.filter { $0.clientID == nil && $0.courseID == nil }
        case .sprint, .task:
            return nil
        }
        let projectIDs = Set(scopedProjects.map(\.id))
        var scopedTasks = tasks.filter { $0.projectID.map(projectIDs.contains) ?? false }
        if case .unassigned = kind {
            scopedTasks += tasks.filter { $0.projectID == nil && $0.courseID == nil }
        }
        let open = scopedTasks.filter { !$0.isComplete }
        return WorkRowContext(
            projectCount: {
                if case .project = kind { return 0 }
                return scopedProjects.count
            }(),
            openTaskCount: open.count,
            overdueTaskCount: open.filter { ($0.dueDate ?? .distantFuture) < dayStart }.count
        )
    }

    /// The "Needs organizing" counts (issue #109's neighbour): work with no
    /// Client above it. Surfaced as a separate section rather than as a
    /// pseudo-Client row, since Unassigned isn't a Client.
    public static func needsOrganizing(
        projects: [Project], tasks: [PCCTask]
    ) -> (projects: Int, tasks: Int) {
        (
            projects.filter { $0.clientID == nil && $0.courseID == nil }.count,
            tasks.filter { $0.projectID == nil && $0.courseID == nil && !$0.isComplete }.count
        )
    }
}

/// How soon something is due, as the row actually renders it. An enum rather
/// than a formatted string so the ordering, the wording and the styling
/// (an overdue row is coloured differently) all read the same one value.
public enum WorkUrgency: Equatable, Sendable {
    case overdue(days: Int)
    /// Due today, carrying the due date so the row can show its clock time.
    case today(Date)
    case tomorrow
    /// Due inside the coming week — rendered as a weekday.
    case thisWeek(Date)
    case later(Date)
    case undated

    public var isOverdue: Bool {
        if case .overdue = self { return true }
        return false
    }

    /// The row's label. Reads `Calendar.current`'s locale formatting for the
    /// dated cases, the same way `SchoolTerm.label` does — this is display
    /// text, not a calculation a test needs to pin.
    public var label: String {
        switch self {
        case .overdue(let days):
            return days == 1 ? "Overdue by 1 day" : "Overdue by \(days) days"
        case .today(let date):
            return "Due \(WorkUrgency.timeFormatter.string(from: date))"
        case .tomorrow:
            return "Due tomorrow"
        case .thisWeek(let date):
            return "Due \(WorkUrgency.weekdayFormatter.string(from: date))"
        case .later(let date):
            return "Due \(WorkUrgency.dateFormatter.string(from: date))"
        case .undated:
            return "No deadline"
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}

/// One row of the Today card: the Task plus the names and figures its row
/// shows. Resolved once here rather than looked up per row while rendering,
/// so the view stays a thin drawing of this list — the same shape
/// `SchoolPriorityTask` takes on the School side.
public struct WorkPriorityTask: Identifiable, Equatable, Sendable {
    public let task: PCCTask
    /// The Client above this Task's Project, when it has one.
    public let clientName: String?
    /// The Project this Task sits in, when it sits in one at all.
    public let projectName: String?
    /// Seconds logged against this Task today — the row's "how far in am I"
    /// figure, and zero for a Task not started yet.
    public let loggedTodaySeconds: Double

    public var id: UUID { task.id }

    public init(task: PCCTask, clientName: String?, projectName: String?, loggedTodaySeconds: Double) {
        self.task = task
        self.clientName = clientName
        self.projectName = projectName
        self.loggedTodaySeconds = loggedTodaySeconds
    }
}

/// The figures on the Today card's summary line.
public struct WorkTodaySummary: Equatable, Sendable {
    /// Seconds logged across every work container today, running timer
    /// excluded.
    public let loggedSeconds: Double
    /// Open work Tasks in total — the backlog the queue is a window onto.
    public let openTasks: Int
    public let overdueTasks: Int
    public let dueTodayTasks: Int

    public init(loggedSeconds: Double, openTasks: Int, overdueTasks: Int, dueTodayTasks: Int) {
        self.loggedSeconds = loggedSeconds
        self.openTasks = openTasks
        self.overdueTasks = overdueTasks
        self.dueTodayTasks = dueTodayTasks
    }
}

/// One heading's worth of the Upcoming card — a calendar day, or the single
/// leading overdue group (`day` is `nil` there, since overdue items span many
/// past days and share one heading).
public struct WorkDeadlineGroup: Identifiable, Equatable, Sendable {
    public let day: Date?
    public let isOverdue: Bool
    public let items: [DeadlineItem]

    public var id: String { isOverdue ? "overdue" : "\(day?.timeIntervalSince1970 ?? 0)" }

    public init(day: Date?, isOverdue: Bool, items: [DeadlineItem]) {
        self.day = day
        self.isOverdue = isOverdue
        self.items = items
    }
}

/// The counts a Client or Project tree row shows under its name.
public struct WorkRowContext: Equatable, Sendable {
    /// Projects under this row — zero for a Project row, which *is* the
    /// project rather than containing any.
    public let projectCount: Int
    public let openTaskCount: Int
    public let overdueTaskCount: Int

    public init(projectCount: Int, openTaskCount: Int, overdueTaskCount: Int) {
        self.projectCount = projectCount
        self.openTaskCount = openTaskCount
        self.overdueTaskCount = overdueTaskCount
    }

    /// The row's caption, e.g. "3 projects · 5 open · 1 overdue". `nil` when
    /// there is nothing worth saying, so an empty Client row stays quiet
    /// rather than reading "0 projects · 0 open".
    public var caption: String? {
        var parts: [String] = []
        if projectCount > 0 {
            parts.append(projectCount == 1 ? "1 project" : "\(projectCount) projects")
        }
        if openTaskCount > 0 { parts.append("\(openTaskCount) open") }
        if overdueTaskCount > 0 { parts.append("\(overdueTaskCount) overdue") }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }
}
