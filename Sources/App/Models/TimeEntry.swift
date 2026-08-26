import Fluent
import Vapor

/// A record spanning a start and end time (`CONTEXT.md`), captured either by
/// starting/stopping a live timer (ticket #28) or via manual entry — the
/// "type it in after the fact" fallback the glossary describes. A row
/// mid-timer has `endDate == nil` (`isRunning`); every other row — manually
/// entered, or a timer that's been stopped — has a concrete `endDate`.
/// Attaches to exactly one of Task, Project, Client, or Course —
/// required, never none, never more than one
/// (`docs/adr/0004-time-entry-container-includes-course.md`), the same
/// alternate-container shape as `PCCTask.container` (ADR-0003) extended to a
/// fourth peer.
///
/// All four foreign keys are optional at the Fluent/Postgres level — only
/// one is ever non-nil for a given row, `TimeEntryController` enforces the
/// exclusivity at write time — but each uses `.cascade` (`CreateTimeEntry`),
/// not `.setNull` like `PCCTask.project`/`course`: a Time Entry can't
/// legally exist container-less. In practice that cascade is a
/// database-level fallback only: `TaskController`/`ProjectController`/
/// `ClientController`/`CourseController.delete` each reject deleting a
/// Task/Project/Client/Course while any Time Entry still references it
/// (ticket #29), so the API never actually reaches the point of cascading a
/// delete onto a Time Entry — the owner must reassign or delete those Time
/// Entries first.
final class TimeEntry: Model, @unchecked Sendable {
    static let schema = "time_entries"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "start_date")
    var startDate: Date

    /// `nil` while this Time Entry is a running live timer (ticket #28,
    /// `MakeTimeEntryEndDateOptional`) — see `isRunning`. Always non-nil for
    /// a manually-entered Time Entry and for a timer once stopped.
    @OptionalField(key: "end_date")
    var endDate: Date?

    @OptionalField(key: "notes")
    var notes: String?

    @OptionalParent(key: "task_id")
    var task: PCCTask?

    @OptionalParent(key: "project_id")
    var project: Project?

    @OptionalParent(key: "client_id")
    var client: PCCClient?

    @OptionalParent(key: "course_id")
    var course: Course?

    init() {}

    init(
        id: UUID? = nil,
        startDate: Date,
        endDate: Date? = nil,
        notes: String? = nil,
        container: TimeEntryContainer
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.notes = notes
        setContainer(container)
    }

    /// `true` while this Time Entry is an in-progress live timer (ticket
    /// #28) — no `endDate` yet.
    var isRunning: Bool { endDate == nil }

    /// The one foreign key that's actually set, read back as a
    /// `TimeEntryContainer` — `nil` only for a row in a state no write path
    /// here produces (see the type's doc comment).
    var container: TimeEntryContainer? {
        if let taskID = $task.id { return .task(taskID) }
        if let projectID = $project.id { return .project(projectID) }
        if let clientID = $client.id { return .client(clientID) }
        if let courseID = $course.id { return .course(courseID) }
        return nil
    }

    /// Sets this Time Entry's container, clearing the other three foreign
    /// keys — the single place that enforces "exactly one" at write time,
    /// mirroring `PCCTask.setContainer`.
    func setContainer(_ container: TimeEntryContainer) {
        $task.id = nil
        $project.id = nil
        $client.id = nil
        $course.id = nil
        switch container {
        case .task(let id): $task.id = id
        case .project(let id): $project.id = id
        case .client(let id): $client.id = id
        case .course(let id): $course.id = id
        }
    }
}
