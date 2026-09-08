import Foundation
import Testing

@testable import PCCUI

/// Covers `WorkBoard` — the Work screen's priority queue, deadline horizon
/// and tree-row context (issues #101, #103, #105). Pure logic with no view
/// model or live backend involved, matching the rest of `PCCUITests`.
@Suite("WorkBoard")
struct WorkBoardTests {
    /// A fixed "today" so nothing here depends on when the tests run, in a
    /// UTC calendar so day boundaries land where the assertions expect.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)  // 2023-11-14 22:13 UTC

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// `days` whole days from the start of the reference day, plus `hours`.
    private func day(_ days: Int, hours: Int = 12) -> Date {
        let start = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: days, to: start)!
            .addingTimeInterval(TimeInterval(hours) * 3600)
    }

    private func entry(taskID: UUID? = nil, projectID: UUID? = nil, start: Date, seconds: TimeInterval?)
        -> TimeEntry
    {
        TimeEntry(
            id: UUID(), startDate: start, endDate: seconds.map { start.addingTimeInterval($0) },
            taskID: taskID, projectID: projectID)
    }

    // MARK: - Priority queue

    @Test("the queue is ordered overdue, then due today, then upcoming, then undated")
    func queueOrdering() {
        let project = Project(id: UUID(), name: "Rebuild", clientID: UUID())
        let overdue = PCCTask(id: UUID(), title: "Late", projectID: project.id, dueDate: day(-2))
        let today = PCCTask(id: UUID(), title: "Now", projectID: project.id, dueDate: day(0, hours: 16))
        let soon = PCCTask(id: UUID(), title: "Soon", projectID: project.id, dueDate: day(3))
        let undated = PCCTask(id: UUID(), title: "Someday", projectID: project.id)

        let queue = WorkBoard.priorityQueue(
            tasks: [undated, soon, today, overdue], projects: [project], clients: [],
            timeEntries: [], calendar: calendar, reference: now)

        #expect(queue.map(\.task.title) == ["Late", "Now", "Soon", "Someday"])
    }

    @Test("completed and Course-owned Tasks never reach the queue")
    func queueExclusions() {
        let course = Course(id: UUID(), name: "Thermo", term: makeTerm())
        let courseProject = Project(id: UUID(), name: "Problem Sets", courseID: course.id)
        let workProject = Project(id: UUID(), name: "Rebuild", clientID: UUID())
        let done = PCCTask(id: UUID(), title: "Done", isComplete: true, projectID: workProject.id)
        let viaProject = PCCTask(id: UUID(), title: "Set 4", projectID: courseProject.id)
        let direct = PCCTask(id: UUID(), title: "Reading", courseID: course.id)
        let kept = PCCTask(id: UUID(), title: "Invoice", projectID: workProject.id)

        let queue = WorkBoard.priorityQueue(
            tasks: [done, viaProject, direct, kept], projects: [courseProject, workProject],
            clients: [], timeEntries: [], calendar: calendar, reference: now)

        #expect(queue.map(\.task.title) == ["Invoice"])
    }

    @Test("a queue row carries its Client, its Project, and its time logged today")
    func queueRowContext() {
        let client = PCCClient(id: UUID(), name: "Northside Studio")
        let project = Project(id: UUID(), name: "Rebuild", clientID: client.id)
        let task = PCCTask(id: UUID(), title: "API", projectID: project.id, dueDate: day(0))
        let entries = [
            entry(taskID: task.id, start: day(0, hours: 9), seconds: 3600),
            entry(taskID: task.id, start: day(-1, hours: 9), seconds: 7200),  // yesterday
            entry(taskID: task.id, start: day(0, hours: 11), seconds: nil),  // still running
        ]

        let row = WorkBoard.priorityQueue(
            tasks: [task], projects: [project], clients: [client], timeEntries: entries,
            calendar: calendar, reference: now)[0]

        #expect(row.clientName == "Northside Studio")
        #expect(row.projectName == "Rebuild")
        #expect(row.loggedTodaySeconds == 3600)
    }

    // MARK: - Today summary

    @Test("the summary counts today's hours, the open backlog, overdue and due-today")
    func summaryCounts() {
        let project = Project(id: UUID(), name: "Rebuild", clientID: UUID())
        let tasks = [
            PCCTask(id: UUID(), title: "Late", projectID: project.id, dueDate: day(-1)),
            PCCTask(id: UUID(), title: "Now", projectID: project.id, dueDate: day(0, hours: 16)),
            PCCTask(id: UUID(), title: "Later", projectID: project.id, dueDate: day(5)),
            PCCTask(id: UUID(), title: "Done", isComplete: true, projectID: project.id, dueDate: day(-3)),
        ]
        let entries = [
            entry(taskID: tasks[0].id, start: day(0, hours: 9), seconds: 1800),
            // Logged straight against a Project rather than a Task — counts
            // toward the day's total even though no queue row shows it.
            entry(projectID: project.id, start: day(0, hours: 10), seconds: 1800),
            entry(taskID: tasks[1].id, start: day(-1, hours: 9), seconds: 3600),
        ]

        let summary = WorkBoard.todaySummary(
            tasks: tasks, projects: [project], timeEntries: entries,
            calendar: calendar, reference: now)

        #expect(summary.loggedSeconds == 3600)
        #expect(summary.openTasks == 3)
        #expect(summary.overdueTasks == 1)
        #expect(summary.dueTodayTasks == 1)
    }

    // MARK: - Urgency

    @Test("urgency is measured in whole days, so this morning's deadline isn't late by noon")
    func urgencyBuckets() {
        func urgency(_ date: Date?) -> WorkUrgency {
            WorkBoard.urgency(for: date, calendar: calendar, reference: now)
        }

        #expect(urgency(day(-2)) == .overdue(days: 2))
        #expect(urgency(day(0, hours: 6)) == .today(day(0, hours: 6)))
        #expect(urgency(day(1)) == .tomorrow)
        #expect(urgency(day(4)) == .thisWeek(day(4)))
        #expect(urgency(day(30)) == .later(day(30)))
        #expect(urgency(nil) == .undated)
        #expect(urgency(day(-1)).isOverdue)
    }

    // MARK: - Deadline horizon

    @Test("the horizon keeps work-side items, drops Course ones, and leads with overdue")
    func upcomingGrouping() {
        let course = Course(id: UUID(), name: "Thermo", term: makeTerm())
        let courseProject = Project(id: UUID(), name: "Problem Sets", courseID: course.id)
        let workProject = Project(id: UUID(), name: "Rebuild", clientID: UUID())
        let workTask = PCCTask(id: UUID(), title: "API", projectID: workProject.id)
        let courseTask = PCCTask(id: UUID(), title: "Set 4", projectID: courseProject.id)

        let deadlines = [
            DeadlineItem(kind: .task, id: workTask.id, title: "API", dueDate: day(-3), isComplete: false),
            DeadlineItem(kind: .project, id: workProject.id, title: "Rebuild", dueDate: day(1)),
            DeadlineItem(kind: .task, id: courseTask.id, title: "Set 4", dueDate: day(1), isComplete: false),
            DeadlineItem(kind: .project, id: courseProject.id, title: "Problem Sets", dueDate: day(2)),
            DeadlineItem(kind: .course, id: course.id, title: "Thermo", dueDate: day(2)),
            // Beyond the horizon, and one already finished.
            DeadlineItem(kind: .task, id: workTask.id, title: "Far", dueDate: day(20), isComplete: false),
            DeadlineItem(kind: .task, id: workTask.id, title: "Finished", dueDate: day(1), isComplete: true),
        ]

        let groups = WorkBoard.upcoming(
            deadlines: deadlines, tasks: [workTask, courseTask], projects: [workProject, courseProject],
            calendar: calendar, reference: now)

        #expect(groups.count == 2)
        #expect(groups[0].isOverdue)
        #expect(groups[0].items.map(\.title) == ["API"])
        #expect(groups[1].day == calendar.startOfDay(for: day(1)))
        #expect(groups[1].items.map(\.title) == ["Rebuild"])
    }

    // MARK: - Row context

    @Test("row context counts Projects and open Tasks for a Client, and only Tasks for a Project")
    func rowContextCounts() {
        let client = PCCClient(id: UUID(), name: "Northside Studio")
        let one = Project(id: UUID(), name: "Rebuild", clientID: client.id)
        let two = Project(id: UUID(), name: "Retainer", clientID: client.id)
        let tasks = [
            PCCTask(id: UUID(), title: "Late", projectID: one.id, dueDate: day(-1)),
            PCCTask(id: UUID(), title: "Open", projectID: one.id, dueDate: day(4)),
            PCCTask(id: UUID(), title: "Done", isComplete: true, projectID: two.id),
        ]

        let clientContext = WorkBoard.rowContext(
            for: .client(client.id), projects: [one, two], tasks: tasks,
            calendar: calendar, reference: now)
        #expect(
            clientContext
                == WorkRowContext(
                    projectCount: 2, openTaskCount: 2, overdueTaskCount: 1,
                    completeTaskCount: 1, totalTaskCount: 3))
        #expect(clientContext?.caption == "2 projects  ·  2 open  ·  1 overdue")

        let projectContext = WorkBoard.rowContext(
            for: .project(one.id), projects: [one, two], tasks: tasks,
            calendar: calendar, reference: now)
        #expect(
            projectContext
                == WorkRowContext(
                    projectCount: 0, openTaskCount: 2, overdueTaskCount: 1,
                    completeTaskCount: 0, totalTaskCount: 2))

        // Leaf rows carry no caption — the tree still has to read as a tree.
        #expect(
            WorkBoard.rowContext(
                for: .task(tasks[0].id), projects: [one], tasks: tasks,
                calendar: calendar, reference: now) == nil)
    }

    @Test("a row with nothing to say has no caption rather than a row of zeroes")
    func emptyRowContextHasNoCaption() {
        let client = PCCClient(id: UUID(), name: "Quiet")
        let context = WorkBoard.rowContext(
            for: .client(client.id), projects: [], tasks: [], calendar: calendar, reference: now)
        #expect(context?.caption == nil)
    }

    // MARK: - Progress

    @Test("a Client's progress aggregates every Task across its Projects")
    func clientProgressAggregates() {
        let client = PCCClient(id: UUID(), name: "Northside Studio")
        let one = Project(id: UUID(), name: "Rebuild", clientID: client.id)
        let two = Project(id: UUID(), name: "Retainer", clientID: client.id)
        let tasks = [
            PCCTask(id: UUID(), title: "A", isComplete: true, projectID: one.id),
            PCCTask(id: UUID(), title: "B", projectID: one.id),
            PCCTask(id: UUID(), title: "C", isComplete: true, projectID: two.id),
            PCCTask(id: UUID(), title: "D", isComplete: true, projectID: two.id),
        ]

        let clientContext = WorkBoard.rowContext(
            for: .client(client.id), projects: [one, two], tasks: tasks,
            calendar: calendar, reference: now)
        #expect(clientContext?.completionFraction == 0.75)

        let projectContext = WorkBoard.rowContext(
            for: .project(one.id), projects: [one, two], tasks: tasks,
            calendar: calendar, reference: now)
        #expect(projectContext?.completionFraction == 0.5)
    }

    @Test("a row with no Tasks has no progress fraction rather than 0% or 100%")
    func emptyRowHasNoProgress() {
        let client = PCCClient(id: UUID(), name: "Quiet")
        let project = Project(id: UUID(), name: "Empty", clientID: client.id)
        let context = WorkBoard.rowContext(
            for: .client(client.id), projects: [project], tasks: [],
            calendar: calendar, reference: now)
        #expect(context?.totalTaskCount == 0)
        #expect(context?.completionFraction == nil)
    }

    // MARK: - Workload

    @Test("a full week is planned at 40 hours, weekends at nothing")
    func weeklyPlan() {
        // The reference week's seven days, Monday through Sunday.
        let week = (0..<7).map { day($0 - 1, hours: 0) }
        let workload = WorkBoard.workload(
            days: week, loggedSeconds: 33 * 3600, calendar: calendar)

        #expect(workload.plannedSeconds == 40 * 3600)
        #expect(workload.remainingSeconds == 7 * 3600)
        #expect(workload.isOverPlan == false)
    }

    @Test("one weekday plans 8 hours and one weekend day plans none")
    func singleDayPlan() {
        let tuesday = calendar.startOfDay(for: day(0))
        #expect(!calendar.isDateInWeekend(tuesday))
        let weekday = WorkBoard.workload(days: [tuesday], loggedSeconds: 0, calendar: calendar)
        #expect(weekday.plannedSeconds == 8 * 3600)

        let saturday = calendar.startOfDay(for: day(4))
        #expect(calendar.isDateInWeekend(saturday))
        let weekend = WorkBoard.workload(days: [saturday], loggedSeconds: 3600, calendar: calendar)
        #expect(weekend.plannedSeconds == 0)
        #expect(weekend.fraction == nil)
        // Logged past a zero plan is still not "over plan" — there was no
        // plan to exceed, which is what a Saturday means.
        #expect(weekend.isOverPlan == false)
    }

    @Test("past the plan, remaining floors at zero and the overage is flagged")
    func overPlan() {
        let tuesday = calendar.startOfDay(for: day(0))
        let workload = WorkBoard.workload(
            days: [tuesday], loggedSeconds: 10 * 3600, calendar: calendar)
        #expect(workload.remainingSeconds == 0)
        #expect(workload.isOverPlan)
    }

    // MARK: - Needs organizing

    @Test("needs-organizing counts Client-less Projects and container-less open Tasks")
    func needsOrganizingCounts() {
        let course = Course(id: UUID(), name: "Thermo", term: makeTerm())
        let projects = [
            Project(id: UUID(), name: "Loose", clientID: nil),
            Project(id: UUID(), name: "Filed", clientID: UUID()),
            Project(id: UUID(), name: "School", courseID: course.id),
        ]
        let tasks = [
            PCCTask(id: UUID(), title: "Floating"),
            PCCTask(id: UUID(), title: "Floating done", isComplete: true),
            PCCTask(id: UUID(), title: "School", courseID: course.id),
        ]

        let counts = WorkBoard.needsOrganizing(projects: projects, tasks: tasks)
        #expect(counts.projects == 1)
        #expect(counts.tasks == 1)
    }

    // MARK: - Task progress

    @Test("progress leads with done over total across every Task in scope")
    func progressTotals() {
        let tasks = [
            PCCTask(id: UUID(), title: "One", isComplete: true),
            PCCTask(id: UUID(), title: "Two", isComplete: true),
            PCCTask(id: UUID(), title: "Three"),
        ]

        let progress = WorkBoard.taskProgress(tasks: tasks, calendar: calendar, reference: now)

        #expect(progress.complete == 2)
        #expect(progress.total == 3)
        #expect(progress.fraction == 2.0 / 3.0)
    }

    @Test("today and this week count only Tasks due inside those windows")
    func progressWindows() {
        let tasks = [
            // Today: one done, one open.
            PCCTask(id: UUID(), title: "Today done", isComplete: true, dueDate: day(0, hours: 9)),
            PCCTask(id: UUID(), title: "Today open", dueDate: day(0, hours: 20)),
            // Elsewhere in the same week (Sun 12th - Sat 18th).
            PCCTask(id: UUID(), title: "Week done", isComplete: true, dueDate: day(-2)),
            PCCTask(id: UUID(), title: "Week open", dueDate: day(4)),
            // Outside the week on either side.
            PCCTask(id: UUID(), title: "Last week", dueDate: day(-3)),
            PCCTask(id: UUID(), title: "Next week", dueDate: day(5)),
            // Undated Tasks belong to neither window.
            PCCTask(id: UUID(), title: "Someday"),
        ]

        let progress = WorkBoard.taskProgress(tasks: tasks, calendar: calendar, reference: now)

        #expect(progress.todayComplete == 1)
        #expect(progress.todayTotal == 2)
        #expect(progress.weekComplete == 2)
        #expect(progress.weekTotal == 4)
    }

    @Test("overdue means incomplete with a due date before today")
    func progressOverdue() {
        let tasks = [
            PCCTask(id: UUID(), title: "Late", dueDate: day(-2)),
            // Done, so no longer overdue however late its due date was.
            PCCTask(id: UUID(), title: "Late but done", isComplete: true, dueDate: day(-4)),
            // Earlier today is not overdue: the whole day is still in play.
            PCCTask(id: UUID(), title: "Earlier today", dueDate: day(0, hours: 1)),
            PCCTask(id: UUID(), title: "Undated"),
        ]

        let progress = WorkBoard.taskProgress(tasks: tasks, calendar: calendar, reference: now)

        #expect(progress.overdue == 1)
    }

    @Test("an empty scope reports zeroes and no fraction rather than dividing by zero")
    func progressEmptyScope() {
        let progress = WorkBoard.taskProgress(tasks: [], calendar: calendar, reference: now)

        #expect(progress.total == 0)
        #expect(progress.complete == 0)
        #expect(progress.overdue == 0)
        #expect(progress.fraction == nil)
        #expect(progress.isEmpty)
    }

    // MARK: - Recent activity

    /// The whole reference day.
    private var today: (start: Date, end: Date) {
        let start = calendar.startOfDay(for: now)
        return (start, calendar.date(byAdding: .day, value: 1, to: start)!)
    }

    @Test("completions and logged time merge into one feed, newest first")
    func activityMerging() {
        let client = PCCClient(id: UUID(), name: "Northside")
        let project = Project(id: UUID(), name: "Payments", clientID: client.id)
        let done = PCCTask(
            id: UUID(), title: "API authentication", isComplete: true, projectID: project.id,
            completedAt: day(0, hours: 14))
        let open = PCCTask(id: UUID(), title: "Dashboard", projectID: project.id)
        let entry = self.entry(projectID: project.id, start: day(0, hours: 9), seconds: 3600)

        let feed = WorkBoard.recentActivity(
            tasks: [done, open], timeEntries: [entry], projects: [project], clients: [client],
            range: today)

        #expect(feed.map(\.headline) == ["Completed API authentication", "Logged 1h 0m"])
        #expect(feed.map(\.kind) == [.taskCompleted, .timeLogged])
        #expect(feed.allSatisfy { $0.context == "Northside" })
    }

    @Test("a Task completed with no completedAt never reaches the feed")
    func activitySkipsUnstampedCompletions() {
        let project = Project(id: UUID(), name: "Payments", clientID: UUID())
        let legacy = PCCTask(
            id: UUID(), title: "Old work", isComplete: true, projectID: project.id)

        let feed = WorkBoard.recentActivity(
            tasks: [legacy], timeEntries: [], projects: [project], clients: [], range: today)

        #expect(feed.isEmpty)
    }

    @Test("a running Time Entry is history yet to happen, so it stays out of the feed")
    func activitySkipsRunningEntries() {
        let running = entry(start: day(0, hours: 10), seconds: nil)

        let feed = WorkBoard.recentActivity(
            tasks: [], timeEntries: [running], projects: [], clients: [], range: today)

        #expect(feed.isEmpty)
    }

    @Test("events outside the range are excluded at both ends")
    func activityRange() {
        let project = Project(id: UUID(), name: "Payments", clientID: UUID())
        let yesterday = PCCTask(
            id: UUID(), title: "Yesterday", isComplete: true, projectID: project.id,
            completedAt: day(-1))
        let tomorrow = PCCTask(
            id: UUID(), title: "Tomorrow", isComplete: true, projectID: project.id,
            completedAt: day(1))
        let inRange = PCCTask(
            id: UUID(), title: "Today", isComplete: true, projectID: project.id,
            completedAt: day(0, hours: 8))

        let feed = WorkBoard.recentActivity(
            tasks: [yesterday, tomorrow, inRange], timeEntries: [], projects: [project],
            clients: [], range: today)

        #expect(feed.map(\.headline) == ["Completed Today"])
    }

    @Test("logged time is timestamped by when it ended, and names its Task")
    func activityLoggedTimeContext() {
        let task = PCCTask(id: UUID(), title: "Refactor", projectID: UUID())
        let entry = self.entry(taskID: task.id, start: day(0, hours: 9), seconds: 5100)

        let feed = WorkBoard.recentActivity(
            tasks: [task], timeEntries: [entry], projects: [], clients: [], range: today)

        #expect(feed[0].date == day(0, hours: 9).addingTimeInterval(5100))
        #expect(feed[0].headline == "Logged 1h 25m")
        #expect(feed[0].context == "Refactor")
        #expect(feed[0].seconds == 5100)
    }

    @Test("an event with nothing above it carries no context rather than a placeholder")
    func activityWithoutContext() {
        let orphan = PCCTask(
            id: UUID(), title: "Loose end", isComplete: true, completedAt: day(0, hours: 11))

        let feed = WorkBoard.recentActivity(
            tasks: [orphan], timeEntries: [], projects: [], clients: [], range: today)

        #expect(feed[0].context == nil)
    }

    // MARK: - Client health

    /// One Client with one Project, and whatever Tasks the case needs.
    private func health(
        clientName: String = "Northside", tasks: [PCCTask] = [], projectDueDate: Date? = nil,
        seconds: Double = 0
    ) -> WorkClientHealth {
        let client = PCCClient(id: UUID(), name: clientName)
        let project = Project(
            id: UUID(), name: "Rebuild", dueDate: projectDueDate, clientID: client.id)
        let scoped = tasks.map {
            PCCTask(
                id: $0.id, title: $0.title, isComplete: $0.isComplete, projectID: project.id,
                dueDate: $0.dueDate)
        }
        return WorkBoard.clientHealth(
            clients: [client], projects: [project], tasks: scoped,
            secondsByClient: [client.id: seconds], calendar: calendar, reference: now)[0]
    }

    @Test("a Client reports active Projects, open and overdue Tasks, its nearest deadline and hours")
    func clientHealthFigures() {
        let summary = health(
            tasks: [
                PCCTask(id: UUID(), title: "Late", dueDate: day(-1)),
                PCCTask(id: UUID(), title: "Soon", dueDate: day(4)),
                PCCTask(id: UUID(), title: "Done", isComplete: true, dueDate: day(-9)),
            ],
            seconds: 8 * 3600)

        #expect(summary.activeProjectCount == 1)
        #expect(summary.openTaskCount == 2)
        #expect(summary.overdueTaskCount == 1)
        #expect(summary.nearestDueDate == day(-1))
        #expect(summary.loggedSeconds == 8 * 3600)
    }

    @Test("a completed Task's due date never counts as the nearest deadline")
    func clientHealthIgnoresCompletedDeadlines() {
        let summary = health(
            tasks: [
                PCCTask(id: UUID(), title: "Done", isComplete: true, dueDate: day(1)),
                PCCTask(id: UUID(), title: "Open", dueDate: day(5)),
            ])

        #expect(summary.nearestDueDate == day(5))
        #expect(!summary.needsAttention)
    }

    @Test("a Project deadline counts even with no dated Task under it")
    func clientHealthUsesProjectDeadlines() {
        let summary = health(
            tasks: [PCCTask(id: UUID(), title: "Undated")], projectDueDate: day(1))

        #expect(summary.nearestDueDate == day(1))
        #expect(summary.needsAttention)
    }

    @Test("a Project whose every Task is done is no longer active")
    func clientHealthActiveProjects() {
        let summary = health(
            tasks: [PCCTask(id: UUID(), title: "Done", isComplete: true)])

        #expect(summary.activeProjectCount == 0)
        #expect(summary.openTaskCount == 0)
    }

    // The attention rule's boundaries: overdue and tomorrow fire, the day
    // after tomorrow does not.
    @Test("attention fires on an overdue Task")
    func attentionOnOverdue() {
        #expect(health(tasks: [PCCTask(id: UUID(), title: "Late", dueDate: day(-1))]).needsAttention)
    }

    @Test("attention fires on work due today and tomorrow, but not the day after")
    func attentionDeadlineBoundary() {
        #expect(health(tasks: [PCCTask(id: UUID(), title: "Now", dueDate: day(0, hours: 23))])
            .needsAttention)
        #expect(health(tasks: [PCCTask(id: UUID(), title: "Next", dueDate: day(1))]).needsAttention)
        #expect(!health(tasks: [PCCTask(id: UUID(), title: "Later", dueDate: day(2))])
            .needsAttention)
    }

    @Test("a Client with nothing dated and nothing late never needs attention")
    func attentionQuietClient() {
        #expect(!health(tasks: [PCCTask(id: UUID(), title: "Someday")]).needsAttention)
    }

    @Test("Clients needing attention sort first, the rest by name")
    func clientHealthOrdering() {
        let calm = PCCClient(id: UUID(), name: "Anvil")
        let alsoCalm = PCCClient(id: UUID(), name: "Zenith")
        let urgent = PCCClient(id: UUID(), name: "Rosabella")
        let projects = [calm, alsoCalm, urgent].map {
            Project(id: UUID(), name: $0.name, clientID: $0.id)
        }
        let late = PCCTask(
            id: UUID(), title: "Late", projectID: projects[2].id, dueDate: day(-3))

        let summaries = WorkBoard.clientHealth(
            clients: [calm, alsoCalm, urgent], projects: projects, tasks: [late],
            secondsByClient: [:], calendar: calendar, reference: now)

        #expect(summaries.map(\.name) == ["Rosabella", "Anvil", "Zenith"])
    }

    @Test("a Course-owned Project never lands under a Client's health")
    func clientHealthExcludesCourseWork() {
        let client = PCCClient(id: UUID(), name: "Northside")
        let course = Course(id: UUID(), name: "Thermo", term: makeTerm())
        let courseProject = Project(
            id: UUID(), name: "Problem Sets", clientID: client.id, courseID: course.id)
        let task = PCCTask(
            id: UUID(), title: "Set 4", projectID: courseProject.id, dueDate: day(-2))

        let summaries = WorkBoard.clientHealth(
            clients: [client], projects: [courseProject], tasks: [task],
            secondsByClient: [:], calendar: calendar, reference: now)

        #expect(summaries[0].activeProjectCount == 0)
        #expect(summaries[0].openTaskCount == 0)
        #expect(!summaries[0].needsAttention)
    }
}
