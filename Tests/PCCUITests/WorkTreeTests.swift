import Foundation
import Testing

@testable import PCCUI

/// Covers `WorkTree.build` — the Work screen's fold rules (ADR-0005), its
/// "the range filters the numbers, not tree membership" rule, and the
/// running-timer exclusion (issue #89). Pure logic with no view model or
/// live backend involved, matching the rest of `PCCUITests`.
@Suite("WorkTree.build")
struct WorkTreeTests {
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

    private func node(_ id: String, in tree: [WorkNode]) -> WorkNode? {
        WorkTree.node(withID: id, in: tree)
    }

    // MARK: - Fold totals

    @Test("a Project's total folds in its Tasks' entries as well as its own")
    func projectFoldsTasks() {
        let project = Project(id: UUID(), name: "Rebuild", clientID: nil)
        let task = PCCTask(id: UUID(), title: "Wireframes", projectID: project.id)
        let tree = WorkTree.build(
            clients: [], projects: [project], sprints: [], tasks: [task],
            timeEntries: [
                entry(taskID: task.id, start: insideRange, seconds: 1800),
                entry(projectID: project.id, start: insideRange, seconds: 600),
            ],
            range: range)

        #expect(node("project:\(project.id)", in: tree)?.totalSeconds == 2400)
        #expect(node("task:\(task.id)", in: tree)?.totalSeconds == 1800)
    }

    @Test("a Client's total folds in its Projects' totals, direct and Task-level")
    func clientFoldsProjects() {
        let client = PCCClient(id: UUID(), name: "Acme")
        let project = Project(id: UUID(), name: "Rebuild", clientID: client.id)
        let task = PCCTask(id: UUID(), title: "Wireframes", projectID: project.id)
        let tree = WorkTree.build(
            clients: [client], projects: [project], sprints: [], tasks: [task],
            timeEntries: [
                entry(taskID: task.id, start: insideRange, seconds: 1800),
                entry(projectID: project.id, start: insideRange, seconds: 600),
                entry(clientID: client.id, start: insideRange, seconds: 300),
            ],
            range: range)

        #expect(node("client:\(client.id)", in: tree)?.totalSeconds == 2700)
    }

    @Test("a Sprint totals its own Tasks and its Project still folds them in once")
    func sprintFold() {
        let project = Project(id: UUID(), name: "Rebuild")
        let sprint = Sprint(
            id: UUID(), name: "Sprint 1", startDate: range.start, endDate: range.end, projectID: project.id)
        let sprinted = PCCTask(id: UUID(), title: "In sprint", projectID: project.id, sprintID: sprint.id)
        let loose = PCCTask(id: UUID(), title: "Outside sprint", projectID: project.id)
        let tree = WorkTree.build(
            clients: [], projects: [project], sprints: [sprint], tasks: [sprinted, loose],
            timeEntries: [
                entry(taskID: sprinted.id, start: insideRange, seconds: 1200),
                entry(taskID: loose.id, start: insideRange, seconds: 300),
            ],
            range: range)

        #expect(node("sprint:\(sprint.id)", in: tree)?.totalSeconds == 1200)
        #expect(node("project:\(project.id)", in: tree)?.totalSeconds == 1500)
    }

    // MARK: - Shape

    @Test("the Sprint level is absent for a Project that uses no Sprints")
    func noEmptySprintLevel() {
        let project = Project(id: UUID(), name: "Rebuild")
        let task = PCCTask(id: UUID(), title: "Wireframes", projectID: project.id)
        let tree = WorkTree.build(
            clients: [], projects: [project], sprints: [], tasks: [task], timeEntries: [], range: range)

        let children = node("project:\(project.id)", in: tree)?.children ?? []
        #expect(children.map(\.id) == ["task:\(task.id)"])
    }

    @Test("a Sprint the owner created but hasn't filled yet is still a row")
    func emptySprintStaysVisible() {
        let project = Project(id: UUID(), name: "Rebuild")
        let sprint = Sprint(
            id: UUID(), name: "Sprint 1", startDate: range.start, endDate: range.end, projectID: project.id)
        let tree = WorkTree.build(
            clients: [], projects: [project], sprints: [sprint], tasks: [], timeEntries: [], range: range)

        // The forbidden empty intermediate row is a Sprint level the tree
        // invents over a Project that uses none — not a real Sprint that has
        // to stay selectable to be renamed or deleted.
        let sprintNode = node("sprint:\(sprint.id)", in: tree)
        #expect(sprintNode != nil)
        #expect(sprintNode?.children == nil)
        #expect(sprintNode?.totalSeconds == 0)
    }

    @Test("a Client-less Project hangs off the synthetic Unassigned node")
    func unassignedNode() {
        let project = Project(id: UUID(), name: "Side work")
        let tree = WorkTree.build(
            clients: [], projects: [project], sprints: [], tasks: [], timeEntries: [], range: range)

        #expect(tree.map(\.id) == ["unassigned"])
        #expect(tree.first?.children?.map(\.id) == ["project:\(project.id)"])
    }

    @Test("Course-owned Projects and Tasks stay off the Work tree entirely")
    func courseWorkExcluded() {
        let courseID = UUID()
        let courseProject = Project(id: UUID(), name: "Group assignment", courseID: courseID)
        let courseTask = PCCTask(id: UUID(), title: "Read chapter 4", courseID: courseID)
        let tree = WorkTree.build(
            clients: [], projects: [courseProject], sprints: [], tasks: [courseTask],
            timeEntries: [], range: range)

        #expect(tree.isEmpty)
    }

    // MARK: - Range and running timers

    @Test("a Project with no hours in range still appears, totalling zero")
    func zeroTimeRowStaysInTree() {
        let project = Project(id: UUID(), name: "Rebuild")
        let task = PCCTask(id: UUID(), title: "Wireframes", projectID: project.id)
        let tree = WorkTree.build(
            clients: [], projects: [project], sprints: [], tasks: [task],
            timeEntries: [
                entry(taskID: task.id, start: range.start.addingTimeInterval(-3600), seconds: 1800)
            ],
            range: range)

        #expect(node("project:\(project.id)", in: tree)?.totalSeconds == 0)
        #expect(node("task:\(task.id)", in: tree) != nil)
    }

    @Test("the range boundary is half-open: start counts, end does not")
    func halfOpenRange() {
        let project = Project(id: UUID(), name: "Rebuild")
        let tree = WorkTree.build(
            clients: [], projects: [project], sprints: [], tasks: [],
            timeEntries: [
                entry(projectID: project.id, start: range.start, seconds: 60),
                entry(projectID: project.id, start: range.end, seconds: 60),
            ],
            range: range)

        #expect(node("project:\(project.id)", in: tree)?.totalSeconds == 60)
    }

    @Test("a running timer contributes nothing until it is stopped")
    func runningTimerExcluded() {
        let project = Project(id: UUID(), name: "Rebuild")
        let tree = WorkTree.build(
            clients: [], projects: [project], sprints: [], tasks: [],
            timeEntries: [entry(projectID: project.id, start: insideRange, seconds: nil)],
            range: range)

        #expect(node("project:\(project.id)", in: tree)?.totalSeconds == 0)
    }
}
