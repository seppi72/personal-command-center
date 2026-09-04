import Foundation

/// The School dashboard's arithmetic (issue #90), with no view or view model
/// involved — the Course-scoped counterpart to `WorkTree`, and testable at
/// this package's pure-logic seam (`SchoolBoardTests`) for the same reason.
///
/// Everything this screen shows is derived from the flat lists
/// `SchoolViewModel` loads once. Nothing here invents a figure the model
/// can't produce: the tiles the ticket deliberately excluded (GPA, Credits
/// Earned, Study Streak) have no function here rather than a placeholder
/// one.
///
/// A pure `enum` namespace with no state, mirroring `WorkTree` and
/// `PCCDuration`.
public enum SchoolBoard {

    // MARK: - Course scope

    /// The Course a Task belongs to, directly (`PCCTask.courseID`) or through
    /// a Course-owned Project (ticket #88's `Project.courseID`) — `nil` for a
    /// Task that isn't school work at all.
    ///
    /// The two paths matter equally: a Task filed under "Thermo / Problem
    /// Sets" carries no `courseID` of its own, only its Project's, and the
    /// backend's Work Hours rollup folds it through that Project the same
    /// way (ADR-0005). Reading only `PCCTask.courseID` would leave every
    /// Project-filed assignment out of this screen entirely.
    public static func courseID(for task: PCCTask, projects: [Project]) -> UUID? {
        if let courseID = task.courseID { return courseID }
        guard let projectID = task.projectID else { return nil }
        return projects.first { $0.id == projectID }?.courseID
    }

    /// Every Task that belongs to some Course, by either path above.
    public static func courseTasks(_ tasks: [PCCTask], projects: [Project]) -> [PCCTask] {
        tasks.filter { courseID(for: $0, projects: projects) != nil }
    }

    /// The Course a Time Entry's logged time counts toward — attached
    /// directly to the Course (ADR-0004), or reached through the Course-owned
    /// Project or Course Task it was logged against. `nil` for Client-side
    /// work, which belongs to the Work screen's own totals (issue #89) and
    /// must never be double-counted here.
    public static func courseID(for entry: TimeEntry, tasks: [PCCTask], projects: [Project]) -> UUID? {
        if let courseID = entry.courseID { return courseID }
        if let taskID = entry.taskID {
            guard let task = tasks.first(where: { $0.id == taskID }) else { return nil }
            return courseID(for: task, projects: projects)
        }
        if let projectID = entry.projectID {
            return projects.first { $0.id == projectID }?.courseID
        }
        return nil
    }

    // MARK: - Priority Tasks

    /// The Priority Tasks list: every *open* Course Task, ordered by Deadline
    /// proximity, each carrying the names its row shows as chips.
    ///
    /// The ordering is the Deadlines screen's own rule, not a second
    /// competing notion of priority — dated Tasks ascending by due date
    /// (which puts overdue ones first, since an overdue date is simply the
    /// earliest), undated ones after every dated one, ties broken by title so
    /// the order is deterministic rather than incidental to load order. That
    /// is exactly `DeadlineController.areInProximityOrder`, restated here
    /// against `PCCTask` because this list is built client-side from Tasks
    /// already loaded rather than re-fetched from `GET /v1/deadlines`.
    ///
    /// Completed Tasks drop off entirely rather than lingering struck
    /// through: this list answers "what is left to do", and a finished
    /// assignment is not an answer to that.
    public static func priorityTasks(
        tasks: [PCCTask], courses: [Course], projects: [Project]
    ) -> [SchoolPriorityTask] {
        courseTasks(tasks, projects: projects)
            .filter { !$0.isComplete }
            .map { task in
                let projectName = task.projectID
                    .flatMap { id in projects.first { $0.id == id } }
                    .flatMap { $0.courseID == nil ? nil : $0.name }
                return SchoolPriorityTask(
                    task: task,
                    courseName: courseID(for: task, projects: projects)
                        .flatMap { id in courses.first { $0.id == id } }?.name,
                    projectName: projectName
                )
            }
            .sorted { areInProximityOrder(($0.task.dueDate, $0.task.title), ($1.task.dueDate, $1.task.title)) }
    }

    /// The one Deadline-proximity rule this screen orders *everything* by —
    /// the Priority list, and the drill-down's own Deadlines section — stated
    /// once here rather than rewritten per list. Takes the two fields the
    /// rule actually reads rather than a particular row type, since the
    /// things being ordered (a Task, a Project, a Course) share no type.
    ///
    /// Named to match the stdlib's two-argument comparator convention (cf.
    /// `sorted(by: areInIncreasingOrder)`) and the backend predicate it
    /// mirrors, `DeadlineController.areInProximityOrder`.
    public static func areInProximityOrder(
        _ lhs: (dueDate: Date?, title: String), _ rhs: (dueDate: Date?, title: String)
    ) -> Bool {
        switch (lhs.dueDate, rhs.dueDate) {
        case let (left?, right?) where left != right:
            return left < right
        case (nil, .some):
            return false
        case (.some, nil):
            return true
        default:
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    // MARK: - Today's Schedule

    /// The Today's Schedule rail: the Course-linked Personal Commitments
    /// falling on `reference`'s calendar day, plus any Course-attached Time
    /// Entry that ran that day, in start-time order.
    ///
    /// Commitments are where exams and quizzes live — they're scheduled, not
    /// completed, so they're Commitments rather than Tasks (`CONTEXT.md`) —
    /// which is why this rail reads Commitments and the Priority list reads
    /// Tasks. Mirrored Calendar events are deliberately absent: the Calendar
    /// is a mirror of an external system whose events aren't necessarily
    /// school-related, and they keep their own screen.
    ///
    /// A Commitment counts as "today" when its span overlaps the day at all,
    /// not only when it starts inside it — a class that began last night and
    /// runs past midnight is still on today's schedule.
    public static func todaySchedule(
        commitments: [PersonalCommitment], timeEntries: [TimeEntry],
        tasks: [PCCTask], projects: [Project], courses: [Course],
        calendar: Calendar = .current, reference: Date = Date()
    ) -> [SchoolScheduleItem] {
        let dayStart = calendar.startOfDay(for: reference)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        func courseName(_ id: UUID?) -> String? {
            id.flatMap { id in courses.first { $0.id == id } }?.name
        }

        let meetings = commitments
            .filter { $0.courseID != nil }
            .filter { $0.startDate < dayEnd && $0.endDate >= dayStart }
            .map {
                SchoolScheduleItem(
                    id: "commitment:\($0.id)", kind: .meeting, title: $0.title,
                    startDate: $0.startDate, endDate: $0.endDate,
                    courseName: courseName($0.courseID))
            }

        let logged = timeEntries
            .filter { $0.startDate < dayEnd && ($0.endDate ?? dayEnd) >= dayStart }
            .compactMap { entry -> SchoolScheduleItem? in
                guard let id = courseID(for: entry, tasks: tasks, projects: projects) else { return nil }
                return SchoolScheduleItem(
                    id: "entry:\(entry.id)", kind: entry.isRunning ? .runningTimer : .loggedTime,
                    title: entry.notes.flatMap { $0.isEmpty ? nil : $0 } ?? courseName(id) ?? "Study",
                    startDate: entry.startDate, endDate: entry.endDate,
                    courseName: courseName(id))
            }

        return (meetings + logged).sorted { lhs, rhs in
            lhs.startDate == rhs.startDate
                ? lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                : lhs.startDate < rhs.startDate
        }
    }

    // MARK: - Tiles

    /// The four KPI tiles across the top — five figures, since "Assignments
    /// Left" carries its own subtitle count.
    ///
    /// Two of them deliberately ignore `range`. "Assignments Left" is a
    /// backlog count — what's still open, full stop — with the range
    /// narrowing only its subtitle ("N due this week"). "Active Courses" is a
    /// roster fact keyed to the Term (see below). Hours Logged and Deadlines
    /// are range-scoped, which is what the stepper above them actually steps;
    /// at the screen's default range (the current week) both read exactly as
    /// the ticket names them.
    ///
    /// Every figure renders even when it's zero rather than being hidden, so
    /// the layout doesn't jump once data arrives — and none of them is a
    /// figure the model can't derive: GPA, Credits Earned and Study Streak
    /// have no function here at all rather than a placeholder one (issue
    /// #92).
    public static func tiles(
        courses: [Course], projects: [Project], tasks: [PCCTask], timeEntries: [TimeEntry],
        range: (start: Date, end: Date), calendar: Calendar = .current, reference: Date = Date()
    ) -> SchoolTiles {
        let schoolTasks = courseTasks(tasks, projects: projects)
        let open = schoolTasks.filter { !$0.isComplete }
        func inRange(_ date: Date?) -> Bool {
            guard let date else { return false }
            return date >= range.start && date < range.end
        }

        // Every school-side Deadline landing in the window, across all three
        // things that can carry one: open Course Tasks, Course-owned
        // Projects, and the Courses themselves — which is what a Deadline is
        // in this domain (`DeadlineItem.Kind`), rather than assignments
        // alone. A completed Task's Deadline is no longer something the week
        // demands.
        let deadlines = open.filter { inRange($0.dueDate) }.count
            + projects.filter { $0.courseID != nil && inRange($0.dueDate) }.count
            + courses.filter { inRange($0.dueDate) }.count

        // Counted against the Term the Courses themselves declare, *not* the
        // calendar month the range starts in. Those differ for most of a
        // Term's life — in November the owner's Courses are still the ones
        // labelled September — and counting by calendar month would make the
        // tile read 0 while the Courses grid directly below it listed every
        // one of them. It's also why this figure alone ignores the range:
        // "Active Courses this Term" is a roster fact, and stepping back a
        // month doesn't change what the owner is enrolled in now.
        let term = currentTerm(in: courses, reference: reference)
        return SchoolTiles(
            assignmentsLeft: open.count,
            assignmentsDueInRange: open.filter { inRange($0.dueDate) }.count,
            loggedSeconds: loggedSeconds(
                tasks: tasks, projects: projects, timeEntries: timeEntries, range: range),
            deadlinesInRange: deadlines,
            activeCourses: courses.filter { SchoolTerm($0) == term }.count
        )
    }

    /// Seconds logged against Course work inside `range` — one Course's when
    /// `courseID` is given, every Course's when it isn't.
    ///
    /// The Hours Logged tile and the drill-down's own hours readout are this
    /// one function at two scopes rather than two loops that have to be kept
    /// agreeing by hand, so the drill-down can't disagree with the tile above
    /// it.
    ///
    /// A running timer contributes to no total until it's stopped
    /// (`CONTEXT.md`), so it's excluded here and surfaces on the schedule
    /// rail as a live row instead.
    public static func loggedSeconds(
        courseID scope: UUID? = nil, tasks: [PCCTask], projects: [Project],
        timeEntries: [TimeEntry], range: (start: Date, end: Date)
    ) -> Double {
        timeEntries.reduce(into: 0.0) { total, entry in
            guard let endDate = entry.endDate else { return }
            guard entry.startDate >= range.start, entry.startDate < range.end else { return }
            guard let id = courseID(for: entry, tasks: tasks, projects: projects) else { return }
            guard scope == nil || scope == id else { return }
            total += endDate.timeIntervalSince(entry.startDate)
        }
    }

    // MARK: - Term

    /// The Term the "This Term" range preset jumps to: the latest Term among
    /// `courses` that has already begun as of `reference`, falling back to
    /// the earliest Term overall when every Course is still upcoming, and
    /// `nil` when there are no Courses at all.
    ///
    /// Derived from the Courses rather than from the calendar, which is the
    /// whole point of the preset — in November, the owner's Courses are still
    /// the ones labelled September, and a preset that just meant "this
    /// calendar month" would duplicate the Month segment beside it. Term
    /// stays a Course label here: it resolves *to* a month-and-year window
    /// rather than becoming a fourth range unit.
    public static func currentTerm(in courses: [Course], reference: Date = Date()) -> SchoolTerm? {
        let terms = courses.map(SchoolTerm.init)
        let today = SchoolTerm.containing(reference)
        return terms.filter { $0 <= today }.max() ?? terms.min()
    }
}

/// One Term — the month and year a Course belongs to (`Course.termMonth`/
/// `termYear`). A value type so the School screen can compare and order
/// Terms without repeating the two-field comparison, and so
/// `SchoolBoard.currentTerm(in:reference:)` has something to return.
public struct SchoolTerm: Equatable, Comparable, Sendable {
    public let month: Int
    public let year: Int

    public init(month: Int, year: Int) {
        self.month = month
        self.year = year
    }

    public init(_ course: Course) {
        self.init(month: course.termMonth, year: course.termYear)
    }

    /// The Term a given date falls in — the calendar month and year around
    /// it, since a Term *is* a month-and-year in this model.
    public static func containing(_ date: Date, calendar: Calendar = .current) -> SchoolTerm {
        SchoolTerm(
            month: calendar.component(.month, from: date),
            year: calendar.component(.year, from: date))
    }

    public static func < (lhs: SchoolTerm, rhs: SchoolTerm) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    /// e.g. "September 2026" — the Term's owner-facing rendering, shared by
    /// the Course cards' caption, the drill-down header and the "This Term"
    /// preset's label. Falls back to a numeric form for an out-of-range month
    /// rather than trapping on the symbol lookup.
    ///
    /// Reads `Calendar.current` directly rather than taking a `calendar:`
    /// parameter like the arithmetic above it: this is the display name of a
    /// month in the owner's own locale, not a calculation whose result a test
    /// needs to pin.
    public var label: String {
        let symbols = Calendar.current.monthSymbols
        guard (1...12).contains(month), symbols.indices.contains(month - 1) else {
            return "\(month)/\(year)"
        }
        return "\(symbols[month - 1]) \(year)"
    }
}

/// One row of the Priority Tasks list: the Task itself plus the names its
/// chips show. Resolved once here rather than looked up per row while
/// rendering, so the view stays a thin drawing of this list and the lookups
/// stay testable.
public struct SchoolPriorityTask: Identifiable, Equatable, Sendable {
    public let task: PCCTask
    /// The owning Course's name — `nil` only if the Course was deleted
    /// between loads.
    public let courseName: String?
    /// The Course-owned Project this Task sits inside, when it sits in one at
    /// all. `nil` for a Task attached straight to its Course.
    public let projectName: String?

    public var id: UUID { task.id }

    public init(task: PCCTask, courseName: String?, projectName: String?) {
        self.task = task
        self.courseName = courseName
        self.projectName = projectName
    }
}

/// One row of the Today's Schedule rail — a class meeting, or time logged
/// against a Course today. Flattened to a common shape so the rail renders
/// one list rather than merging two different types at draw time.
public struct SchoolScheduleItem: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A Course-linked Personal Commitment — a class, exam, or quiz.
        case meeting
        /// A finished Time Entry logged against this Course today.
        case loggedTime
        /// The live timer, if it's running against Course work. Shown, but it
        /// counts toward no total until it's stopped (`CONTEXT.md`).
        case runningTimer
    }

    public let id: String
    public let kind: Kind
    public let title: String
    public let startDate: Date
    /// `nil` for a running timer, which has no end yet.
    public let endDate: Date?
    public let courseName: String?

    public init(
        id: String, kind: Kind, title: String, startDate: Date, endDate: Date?, courseName: String?
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.courseName = courseName
    }
}

/// The four KPI figures across the top of the School screen. A value type
/// rather than four computed properties on the view model, so
/// `SchoolBoardTests` can assert the whole tile row at once against a fixed
/// range.
public struct SchoolTiles: Equatable, Sendable {
    /// Open Course Tasks, regardless of range — the backlog.
    public let assignmentsLeft: Int
    /// How many of those fall due inside the range — the first tile's
    /// subtitle, not a tile of its own.
    public let assignmentsDueInRange: Int
    /// Seconds logged against Course work inside the range, running timer
    /// excluded.
    public let loggedSeconds: Double
    /// Deadlines landing in the range across open Course Tasks, Course-owned
    /// Projects, and Courses themselves.
    public let deadlinesInRange: Int
    /// Courses whose Term is the Term the range starts in.
    public let activeCourses: Int

    public init(
        assignmentsLeft: Int, assignmentsDueInRange: Int, loggedSeconds: Double,
        deadlinesInRange: Int, activeCourses: Int
    ) {
        self.assignmentsLeft = assignmentsLeft
        self.assignmentsDueInRange = assignmentsDueInRange
        self.loggedSeconds = loggedSeconds
        self.deadlinesInRange = deadlinesInRange
        self.activeCourses = activeCourses
    }
}
