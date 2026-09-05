import Foundation
import Testing

@testable import PCCUI

/// Covers `LoggedHours.split` — Overview's cross-domain hours total (issue
/// #91). The acceptance bar is that the total "matches the Work and School
/// dashboards added together", so the load-bearing tests here are the two
/// that check each share against what that dashboard's own code computes
/// (`WorkTree.build` and `SchoolBoard.loggedSeconds`) rather than against a
/// number retyped from this file's own reasoning.
@Suite("LoggedHours.split")
struct LoggedHoursTests {
    /// A fixed window so nothing here depends on when the tests run.
    private let range = (
        start: Date(timeIntervalSince1970: 1_700_000_000),
        end: Date(timeIntervalSince1970: 1_700_604_800)  // + 7 days
    )

    private var insideRange: Date { range.start.addingTimeInterval(3600) }

    private func entry(
        taskID: UUID? = nil, projectID: UUID? = nil, clientID: UUID? = nil, courseID: UUID? = nil,
        start: Date, seconds: TimeInterval?
    ) -> TimeEntry {
        TimeEntry(
            id: UUID(), startDate: start, endDate: seconds.map { start.addingTimeInterval($0) },
            taskID: taskID, projectID: projectID, clientID: clientID, courseID: courseID)
    }

    /// One of everything: a Client with a Project and a Task, a Course with a
    /// Project and a Task, a container-less Task, and entries against each.
    private struct Fixture {
        let client = PCCClient(id: UUID(), name: "Acme")
        let course = Course(id: UUID(), name: "Thermo", termMonth: 11, termYear: 2023)
        let clientProject: Project
        let courseProject: Project
        let clientTask: PCCTask
        let courseTask: PCCTask
        let looseTask: PCCTask

        init() {
            clientProject = Project(id: UUID(), name: "Rebuild", clientID: client.id)
            courseProject = Project(id: UUID(), name: "Problem Sets", courseID: course.id)
            clientTask = PCCTask(id: UUID(), title: "Wireframes", projectID: clientProject.id)
            courseTask = PCCTask(id: UUID(), title: "Set 4", projectID: courseProject.id)
            looseTask = PCCTask(id: UUID(), title: "Errand")
        }

        var projects: [Project] { [clientProject, courseProject] }
        var tasks: [PCCTask] { [clientTask, courseTask, looseTask] }
    }

    // MARK: - The split itself

    @Test("each entry lands in exactly one share, by which dashboard owns it")
    func splitsByDashboard() {
        let fixture = Fixture()
        let entries = [
            entry(clientID: fixture.client.id, start: insideRange, seconds: 600),
            entry(projectID: fixture.clientProject.id, start: insideRange, seconds: 600),
            entry(taskID: fixture.clientTask.id, start: insideRange, seconds: 600),
            entry(taskID: fixture.looseTask.id, start: insideRange, seconds: 600),
            entry(courseID: fixture.course.id, start: insideRange, seconds: 300),
            entry(projectID: fixture.courseProject.id, start: insideRange, seconds: 300),
            entry(taskID: fixture.courseTask.id, start: insideRange, seconds: 300),
        ]

        let split = LoggedHours.split(
            timeEntries: entries, tasks: fixture.tasks, projects: fixture.projects, range: range)

        #expect(split.workSeconds == 2400)
        #expect(split.schoolSeconds == 900)
        #expect(split.totalSeconds == 3300)
    }

    @Test("a running timer counts toward nothing until it is stopped")
    func excludesRunningTimer() {
        let fixture = Fixture()
        let split = LoggedHours.split(
            timeEntries: [
                entry(clientID: fixture.client.id, start: insideRange, seconds: nil),
                entry(courseID: fixture.course.id, start: insideRange, seconds: nil),
            ],
            tasks: fixture.tasks, projects: fixture.projects, range: range)

        #expect(split.totalSeconds == 0)
    }

    @Test("an entry starting outside the range is excluded from every share")
    func excludesOutOfRange() {
        let fixture = Fixture()
        let split = LoggedHours.split(
            timeEntries: [
                entry(clientID: fixture.client.id, start: range.start.addingTimeInterval(-1), seconds: 600),
                entry(courseID: fixture.course.id, start: range.end, seconds: 600),
            ],
            tasks: fixture.tasks, projects: fixture.projects, range: range)

        #expect(split.totalSeconds == 0)
    }

    /// The property that makes this a *total* rather than a subtotal. It
    /// holds because a Time Entry always has exactly one container
    /// (`CONTEXT.md`, ADR-0004), so "not coursework" and "Work" are the same
    /// set — there is no third kind of logged time to lose.
    @Test("the two shares are exhaustive — the total loses no logged second")
    func sharesAreExhaustive() {
        let fixture = Fixture()
        let entries = [
            entry(clientID: fixture.client.id, start: insideRange, seconds: 111),
            entry(projectID: fixture.clientProject.id, start: insideRange, seconds: 222),
            entry(taskID: fixture.looseTask.id, start: insideRange, seconds: 333),
            entry(courseID: fixture.course.id, start: insideRange, seconds: 444),
            entry(taskID: fixture.courseTask.id, start: insideRange, seconds: 555),
        ]

        let split = LoggedHours.split(
            timeEntries: entries, tasks: fixture.tasks, projects: fixture.projects, range: range)

        // Every completed, in-range second the backend's own rollup would
        // count (`WorkHoursController.completedEntries`), with nothing
        // double-counted and nothing dropped.
        #expect(split.workSeconds + split.schoolSeconds == 1665)
        #expect(split.totalSeconds == 1665)
    }

    // MARK: - Agreement with the two dashboards

    /// The acceptance criterion, checked against the School screen's own
    /// code rather than a hand-copied figure.
    @Test("the School share equals what the School dashboard totals")
    func schoolShareMatchesSchoolDashboard() {
        let fixture = Fixture()
        let entries = [
            entry(courseID: fixture.course.id, start: insideRange, seconds: 300),
            entry(projectID: fixture.courseProject.id, start: insideRange, seconds: 300),
            entry(taskID: fixture.courseTask.id, start: insideRange, seconds: 300),
            entry(clientID: fixture.client.id, start: insideRange, seconds: 9999),
        ]

        let split = LoggedHours.split(
            timeEntries: entries, tasks: fixture.tasks, projects: fixture.projects, range: range)
        let school = SchoolBoard.loggedSeconds(
            tasks: fixture.tasks, projects: fixture.projects, timeEntries: entries, range: range)

        #expect(split.schoolSeconds == school)
    }

    /// The other half of the same criterion, against `WorkTree`'s own fold.
    @Test("the Work share equals what the Work dashboard's tree totals")
    func workShareMatchesWorkDashboard() {
        let fixture = Fixture()
        let entries = [
            entry(clientID: fixture.client.id, start: insideRange, seconds: 600),
            entry(projectID: fixture.clientProject.id, start: insideRange, seconds: 600),
            entry(taskID: fixture.clientTask.id, start: insideRange, seconds: 600),
            entry(taskID: fixture.looseTask.id, start: insideRange, seconds: 600),
            entry(courseID: fixture.course.id, start: insideRange, seconds: 9999),
        ]

        let split = LoggedHours.split(
            timeEntries: entries, tasks: fixture.tasks, projects: fixture.projects, range: range)
        let tree = WorkTree.build(
            clients: [fixture.client], projects: fixture.projects, sprints: [],
            tasks: fixture.tasks, timeEntries: entries, range: range)
        let treeTotal = tree.reduce(0) { $0 + $1.totalSeconds }

        #expect(split.workSeconds == treeTotal)
    }

    @Test("Course work never leaks into the Work share, in either direction")
    func noCrossDomainLeak() {
        let fixture = Fixture()
        let entries = [
            entry(projectID: fixture.courseProject.id, start: insideRange, seconds: 600),
            entry(taskID: fixture.courseTask.id, start: insideRange, seconds: 600),
        ]

        let split = LoggedHours.split(
            timeEntries: entries, tasks: fixture.tasks, projects: fixture.projects, range: range)

        #expect(split.workSeconds == 0)
        #expect(split.schoolSeconds == 1200)
    }
}
