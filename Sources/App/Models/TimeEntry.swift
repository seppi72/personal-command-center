import Fluent
import Vapor

/// A record spanning a start and end time (`CONTEXT.md`), captured here via
/// manual entry — the "type it in after the fact" fallback the glossary
/// describes; starting/stopping a live timer is a future slice, not this
/// one. Attaches to exactly one of Task, Project, Client, or Course —
/// required, never none, never more than one
/// (`docs/adr/0004-time-entry-container-includes-course.md`), the same
/// alternate-container shape as `PCCTask.container` (ADR-0003) extended to a
/// fourth peer.
///
/// All four foreign keys are optional at the Fluent/Postgres level — only
/// one is ever non-nil for a given row, `TimeEntryController` enforces the
/// exclusivity at write time — but each uses `.cascade` (`CreateTimeEntry`),
/// not `.setNull` like `PCCTask.project`/`course`: a Time Entry can't
/// legally exist container-less, so deleting the Task/Project/Client/Course
/// it's attached to must delete the Time Entry along with it rather than
/// leave a row with all four foreign keys nil.
final class TimeEntry: Model, @unchecked Sendable {
    static let schema = "time_entries"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "start_date")
    var startDate: Date

    @Field(key: "end_date")
    var endDate: Date

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
        endDate: Date,
        notes: String? = nil,
        container: TimeEntryContainer
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.notes = notes
        setContainer(container)
    }

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
