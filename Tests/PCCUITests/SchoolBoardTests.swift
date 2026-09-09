import Foundation
import Testing

@testable import PCCUI

/// Covers `SchoolBoard` — the School dashboard's priority ordering rule and
/// its tile counts (issue #90), plus the Course-scoping both rest on. Pure
/// logic with no view model or live backend involved, matching the rest of
/// `PCCUITests`.
@Suite("SchoolBoard")
struct SchoolBoardTests {
    /// A fixed window so nothing here depends on when the tests run.
    private let range = (
        start: Date(timeIntervalSince1970: 1_700_000_000),
        end: Date(timeIntervalSince1970: 1_700_604_800)  // + 7 days
    )

    private var insideRange: Date { range.start.addingTimeInterval(3600) }
    private var beforeRange: Date { range.start.addingTimeInterval(-86_400) }
    private var afterRange: Date { range.end.addingTimeInterval(86_400) }

    private func course(
        _ name: String, term: Term? = nil, dueDate: Date? = nil, units: Double = 3,
        grade: Grade? = nil
    ) -> Course {
        Course(
            id: UUID(), name: name, term: term ?? makeTerm(), units: units, grade: grade,
            dueDate: dueDate)
    }

    private func entry(
        taskID: UUID? = nil, projectID: UUID? = nil, clientID: UUID? = nil, courseID: UUID? = nil,
        start: Date, seconds: TimeInterval?
    ) -> TimeEntry {
        TimeEntry(
            id: UUID(), startDate: start, endDate: seconds.map { start.addingTimeInterval($0) },
            taskID: taskID, projectID: projectID, clientID: clientID, courseID: courseID)
    }

    // MARK: - Course scope

    @Test("a Task reaches its Course through a Course-owned Project, not only directly")
    func taskCourseThroughProject() {
        let course = course("Thermo")
        let project = Project(id: UUID(), name: "Problem Sets", courseID: course.id)
        let filed = PCCTask(id: UUID(), title: "Set 4", projectID: project.id)
        let direct = PCCTask(id: UUID(), title: "Reading", courseID: course.id)
        let clientWork = PCCTask(id: UUID(), title: "Invoice", projectID: UUID())

        #expect(SchoolBoard.courseID(for: filed, projects: [project]) == course.id)
        #expect(SchoolBoard.courseID(for: direct, projects: [project]) == course.id)
        #expect(SchoolBoard.courseID(for: clientWork, projects: [project]) == nil)
        #expect(SchoolBoard.courseTasks([filed, direct, clientWork], projects: [project]).count == 2)
    }

    @Test("a Time Entry reaches its Course directly, through a Project, or through a Task")
    func entryCourseScope() {
        let course = course("Thermo")
        let project = Project(id: UUID(), name: "Problem Sets", courseID: course.id)
        let task = PCCTask(id: UUID(), title: "Set 4", projectID: project.id)
        let clientProject = Project(id: UUID(), name: "Rebuild", clientID: UUID())

        let scope = { (e: TimeEntry) in
            SchoolBoard.courseID(for: e, tasks: [task], projects: [project, clientProject])
        }
        #expect(scope(entry(courseID: course.id, start: insideRange, seconds: 60)) == course.id)
        #expect(scope(entry(projectID: project.id, start: insideRange, seconds: 60)) == course.id)
        #expect(scope(entry(taskID: task.id, start: insideRange, seconds: 60)) == course.id)
        #expect(scope(entry(projectID: clientProject.id, start: insideRange, seconds: 60)) == nil)
        #expect(scope(entry(clientID: UUID(), start: insideRange, seconds: 60)) == nil)
    }

    // MARK: - Priority ordering

    @Test("Priority Tasks sort by Deadline proximity, overdue first and undated last")
    func priorityOrdering() {
        let course = course("Thermo")
        func task(_ title: String, due: Date?) -> PCCTask {
            PCCTask(id: UUID(), title: title, dueDate: due, courseID: course.id)
        }
        let tasks = [
            task("Undated", due: nil),
            task("Later", due: afterRange),
            task("Overdue", due: beforeRange),
            task("Soon", due: insideRange),
        ]

        let ordered = SchoolBoard.priorityTasks(tasks: tasks, courses: [course], projects: [])

        #expect(ordered.map(\.task.title) == ["Overdue", "Soon", "Later", "Undated"])
    }

    @Test("Priority Tasks with the same due date fall back to title order, deterministically")
    func priorityTieBreak() {
        let course = course("Thermo")
        func task(_ title: String, due: Date?) -> PCCTask {
            PCCTask(id: UUID(), title: title, dueDate: due, courseID: course.id)
        }
        let ordered = SchoolBoard.priorityTasks(
            tasks: [task("Beta", due: insideRange), task("Alpha", due: insideRange), task("Zeta", due: nil), task("Kappa", due: nil)],
            courses: [course], projects: [])

        #expect(ordered.map(\.task.title) == ["Alpha", "Beta", "Kappa", "Zeta"])
    }

    @Test("a completed Task drops off the Priority list rather than lingering")
    func priorityDropsCompleted() {
        let course = course("Thermo")
        let done = PCCTask(id: UUID(), title: "Set 1", isComplete: true, dueDate: beforeRange, courseID: course.id)
        let open = PCCTask(id: UUID(), title: "Set 2", dueDate: insideRange, courseID: course.id)

        let ordered = SchoolBoard.priorityTasks(tasks: [done, open], courses: [course], projects: [])

        #expect(ordered.map(\.task.title) == ["Set 2"])
    }

    @Test("Client-side Tasks never appear on the Priority list")
    func priorityExcludesClientWork() {
        let course = course("Thermo")
        let clientProject = Project(id: UUID(), name: "Rebuild", clientID: UUID())
        let clientTask = PCCTask(id: UUID(), title: "Wireframes", projectID: clientProject.id, dueDate: beforeRange)
        let courseTask = PCCTask(id: UUID(), title: "Set 2", dueDate: insideRange, courseID: course.id)

        let ordered = SchoolBoard.priorityTasks(
            tasks: [clientTask, courseTask], courses: [course], projects: [clientProject])

        #expect(ordered.map(\.task.title) == ["Set 2"])
    }

    @Test("a Priority row carries its Course chip, and its Project chip only when filed in one")
    func priorityChips() {
        let course = course("Thermo")
        let project = Project(id: UUID(), name: "Problem Sets", courseID: course.id)
        let filed = PCCTask(id: UUID(), title: "Set 4", projectID: project.id, dueDate: insideRange)
        let direct = PCCTask(id: UUID(), title: "Zeta Reading", dueDate: afterRange, courseID: course.id)

        let ordered = SchoolBoard.priorityTasks(
            tasks: [filed, direct], courses: [course], projects: [project])

        #expect(ordered[0].courseName == "Thermo")
        #expect(ordered[0].projectName == "Problem Sets")
        #expect(ordered[1].courseName == "Thermo")
        #expect(ordered[1].projectName == nil)
    }

    // MARK: - Tiles

    @Test("Assignments Left counts every open Course Task, and only those due in range in its subtitle")
    func assignmentTiles() {
        let course = course("Thermo")
        let tasks = [
            PCCTask(id: UUID(), title: "Due in range", dueDate: insideRange, courseID: course.id),
            PCCTask(id: UUID(), title: "Due later", dueDate: afterRange, courseID: course.id),
            PCCTask(id: UUID(), title: "Undated", courseID: course.id),
            PCCTask(id: UUID(), title: "Done", isComplete: true, dueDate: insideRange, courseID: course.id),
            PCCTask(id: UUID(), title: "Client work", dueDate: insideRange),
        ]

        let tiles = SchoolBoard.tiles(
            courses: [course], projects: [], tasks: tasks, timeEntries: [], range: range)

        #expect(tiles.assignmentsLeft == 3)
        #expect(tiles.assignmentsDueInRange == 1)
    }

    @Test("Hours Logged sums only Course time inside the range, excluding the running timer")
    func loggedTile() {
        let course = course("Thermo")
        let project = Project(id: UUID(), name: "Problem Sets", courseID: course.id)
        let entries = [
            entry(courseID: course.id, start: insideRange, seconds: 1800),
            entry(projectID: project.id, start: insideRange, seconds: 600),
            entry(courseID: course.id, start: beforeRange, seconds: 9999),  // out of range
            entry(clientID: UUID(), start: insideRange, seconds: 9999),  // not school work
            entry(courseID: course.id, start: insideRange, seconds: nil),  // running
        ]

        let tiles = SchoolBoard.tiles(
            courses: [course], projects: [project], tasks: [], timeEntries: entries, range: range)

        #expect(tiles.loggedSeconds == 2400)
    }

    @Test("Deadlines in range counts open Course Tasks, Course Projects and Courses together")
    func deadlinesTile() {
        let course = course("Thermo", dueDate: insideRange)
        let courseProject = Project(id: UUID(), name: "Problem Sets", dueDate: insideRange, courseID: course.id)
        let clientProject = Project(id: UUID(), name: "Rebuild", dueDate: insideRange, clientID: UUID())
        let tasks = [
            PCCTask(id: UUID(), title: "Set 4", dueDate: insideRange, courseID: course.id),
            PCCTask(id: UUID(), title: "Set 5", isComplete: true, dueDate: insideRange, courseID: course.id),
            PCCTask(id: UUID(), title: "Set 6", dueDate: afterRange, courseID: course.id),
        ]

        let tiles = SchoolBoard.tiles(
            courses: [course], projects: [courseProject, clientProject], tasks: tasks,
            timeEntries: [], range: range)

        // One open Task + the Course-owned Project + the Course itself. The
        // completed Task, the out-of-range Task and the Client Project are
        // all out.
        #expect(tiles.deadlinesInRange == 3)
    }

    @Test("Active Courses counts the Courses in the Courses' own current Term")
    func activeCoursesTile() {
        let reference = Date(timeIntervalSince1970: 1_700_000_000)
        let tiles = SchoolBoard.tiles(
            courses: [
                course("Thermo", term: currentTerm),
                course("Statics", term: currentTerm),
                course("Last term", term: pastTerm),
            ],
            projects: [], tasks: [], timeEntries: [], range: range, reference: reference)

        #expect(tiles.activeCourses == 2)
    }

    /// The bug this pins: a Term is the Courses' *own* semester, not the
    /// calendar month the range happens to start in. Counting by calendar
    /// month made the tile read 0 for a roster viewed a month later, while
    /// the Courses grid directly below it listed all of them. The range here
    /// sits outside the Term's span entirely and the roster still counts.
    @Test("Active Courses still counts the roster when the range is outside the Term's span")
    func activeCoursesOutsideRange() {
        let reference = Date(timeIntervalSince1970: 1_700_000_000)
        let tiles = SchoolBoard.tiles(
            courses: [course("Thermo", term: currentTerm), course("Statics", term: currentTerm)],
            projects: [], tasks: [], timeEntries: [],
            range: (
                start: reference.addingTimeInterval(400 * 86_400),
                end: reference.addingTimeInterval(407 * 86_400)
            ),
            reference: reference)

        #expect(tiles.activeCourses == 2)
    }

    @Test("the drill-down's hours are the Hours Logged tile narrowed to one Course")
    func loggedSecondsScoping() {
        let thermo = course("Thermo")
        let statics = course("Statics")
        let entries = [
            entry(courseID: thermo.id, start: insideRange, seconds: 1800),
            entry(courseID: statics.id, start: insideRange, seconds: 600),
        ]

        let all = SchoolBoard.loggedSeconds(
            tasks: [], projects: [], timeEntries: entries, range: range)
        let scoped = SchoolBoard.loggedSeconds(
            courseID: thermo.id, tasks: [], projects: [], timeEntries: entries, range: range)

        #expect(all == 2400)
        #expect(scoped == 1800)
        #expect(
            all
                == SchoolBoard.tiles(
                    courses: [thermo, statics], projects: [], tasks: [], timeEntries: entries,
                    range: range
                ).loggedSeconds)
    }

    @Test("every tile renders zeroed rather than absent when there is nothing to count")
    func emptyTiles() {
        let tiles = SchoolBoard.tiles(
            courses: [], projects: [], tasks: [], timeEntries: [], range: range)

        #expect(
            tiles
                == SchoolTiles(
                    assignmentsLeft: 0, assignmentsDueInRange: 0, loggedSeconds: 0,
                    deadlinesInRange: 0, activeCourses: 0))
    }

    // MARK: - Term

    @Test("This Term resolves to the Term whose published span contains today")
    func currentTermContainingToday() {
        let courses = [
            course("Old", term: pastTerm),
            course("Current", term: currentTerm),
            course("Upcoming", term: futureTerm),
        ]

        #expect(SchoolBoard.currentTerm(in: courses, reference: termReference) == currentTerm)
    }

    /// Between semesters no Term contains today, and the screen still has to
    /// name one — the one just finished, not the one that hasn't started.
    @Test("This Term falls back to the most recent Term that has already started")
    func currentTermBetweenSemesters() {
        let betweenSemesters = termReference.addingTimeInterval(120 * 86_400)
        let courses = [course("Old", term: pastTerm), course("Current", term: currentTerm)]

        #expect(SchoolBoard.currentTerm(in: courses, reference: betweenSemesters) == currentTerm)
    }

    /// The dates are what make a Term selectable. A Term whose academic
    /// calendar the owner hasn't filled in yet says nothing about today, so
    /// it is never chosen — "not set yet" must not read as "happening now"
    /// (`docs/adr/0012-term-is-an-entity.md`).
    @Test("This Term never selects a Term with no dates set")
    func currentTermIgnoresUndatedTerms() {
        let undated = makeTerm(year: 2023, semester: .second)
        #expect(
            SchoolBoard.currentTerm(in: [course("Thermo", term: undated)], reference: termReference)
                == nil)
    }

    /// Three Terms with real spans: the one containing `termReference`, the
    /// semester before it, and the one after. Dated, since an undated Term is
    /// never selectable as the current one.
    private let termReference = Date(timeIntervalSince1970: 1_700_000_000)  // Nov 2023

    /// Stored rather than computed: each `makeTerm` call mints a fresh id,
    /// and these tests compare Terms by identity.
    private let currentTerm = makeTerm(
        year: 2023, semester: .first,
        startDate: Date(timeIntervalSince1970: 1_700_000_000 - 60 * 86_400),
        endDate: Date(timeIntervalSince1970: 1_700_000_000 + 30 * 86_400))

    /// The 2nd Semester of the same labelled year runs *earlier* in the
    /// calendar than the 1st at this school, which is why "the most recent
    /// Term" is decided by start date rather than by the Term's own order.
    private let pastTerm = makeTerm(
        year: 2023, semester: .second,
        startDate: Date(timeIntervalSince1970: 1_700_000_000 - 240 * 86_400),
        endDate: Date(timeIntervalSince1970: 1_700_000_000 - 120 * 86_400))

    private let futureTerm = makeTerm(
        year: 2024, semester: .first,
        startDate: Date(timeIntervalSince1970: 1_700_000_000 + 300 * 86_400),
        endDate: Date(timeIntervalSince1970: 1_700_000_000 + 400 * 86_400))

    @Test("This Term is nil with no Courses at all")
    func currentTermNoCourses() {
        #expect(SchoolBoard.currentTerm(in: [], reference: Date()) == nil)
    }

    // MARK: - Today's Schedule

    @Test("Today's Schedule shows Course meetings and Course time, in start order")
    func todaySchedule() {
        let course = course("Thermo")
        let calendar = Calendar.current
        let reference = Date(timeIntervalSince1970: 1_700_000_000)
        let dayStart = calendar.startOfDay(for: reference)
        func atHour(_ hour: Int) -> Date { dayStart.addingTimeInterval(TimeInterval(hour) * 3600) }

        let items = SchoolBoard.todaySchedule(
            commitments: [
                PersonalCommitment(
                    id: UUID(), title: "Lecture", startDate: atHour(10), endDate: atHour(11),
                    courseID: course.id),
                PersonalCommitment(
                    id: UUID(), title: "Dentist", startDate: atHour(9), endDate: atHour(10)),
                PersonalCommitment(
                    id: UUID(), title: "Next week", startDate: atHour(200), endDate: atHour(201),
                    courseID: course.id),
            ],
            timeEntries: [
                entry(courseID: course.id, start: atHour(8), seconds: 3600),
                entry(clientID: UUID(), start: atHour(7), seconds: 3600),
            ],
            tasks: [], projects: [], courses: [course], calendar: calendar, reference: reference)

        // The non-Course Commitment, the Client Time Entry and the Commitment
        // on another day are all absent; the rest are in start order.
        #expect(items.map(\.title) == ["Thermo", "Lecture"])
        #expect(items.map(\.kind) == [.loggedTime, .meeting])
    }

    @Test("a Course meeting spanning midnight is still on today's schedule")
    func todayScheduleOverlap() {
        let course = course("Thermo")
        let calendar = Calendar.current
        let reference = Date(timeIntervalSince1970: 1_700_000_000)
        let dayStart = calendar.startOfDay(for: reference)

        let items = SchoolBoard.todaySchedule(
            commitments: [
                PersonalCommitment(
                    id: UUID(), title: "Night lab",
                    startDate: dayStart.addingTimeInterval(-3600),
                    endDate: dayStart.addingTimeInterval(3600), courseID: course.id)
            ],
            timeEntries: [], tasks: [], projects: [], courses: [course],
            calendar: calendar, reference: reference)

        #expect(items.map(\.title) == ["Night lab"])
    }

    @Test("a running Course timer appears on the rail, marked as running")
    func todayScheduleRunningTimer() {
        let course = course("Thermo")
        let calendar = Calendar.current
        let reference = Date(timeIntervalSince1970: 1_700_000_000)
        let dayStart = calendar.startOfDay(for: reference)

        let items = SchoolBoard.todaySchedule(
            commitments: [],
            timeEntries: [entry(courseID: course.id, start: dayStart.addingTimeInterval(3600), seconds: nil)],
            tasks: [], projects: [], courses: [course], calendar: calendar, reference: reference)

        #expect(items.map(\.kind) == [.runningTimer])
    }
}
