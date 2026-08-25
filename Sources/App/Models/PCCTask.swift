import Fluent
import Vapor

/// The atomic unit of work (`CONTEXT.md`). May belong to a Project or a
/// Course — never both (ADR-0003): the two foreign keys are independently
/// optional (Project-less/Course-less are both valid, ordinary states, not
/// error cases), but `TaskController.assignProject`/`assignCourse` enforce
/// the exclusivity at write time by clearing the other whenever one is set.
/// May also carry a Deadline: a due-date concept (`CONTEXT.md`) modeled here
/// as a plain nullable field rather than its own entity, since nothing about
/// it needs an identity independent of the Task it's attached to.
///
/// Named `PCCTask` in Swift only: an unqualified `Task` here would shadow
/// `_Concurrency.Task` for this whole target (and `PCCUI`, which already
/// relies on bare `Task { ... }` in `ProjectsView`). The domain term "Task"
/// is what shows up everywhere that matters — the `schema`, the JSON API,
/// docs, and UI text.
final class PCCTask: Model, @unchecked Sendable {
    static let schema = "tasks"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "title")
    var title: String

    @OptionalField(key: "notes")
    var notes: String?

    @Field(key: "is_complete")
    var isComplete: Bool

    @OptionalParent(key: "project_id")
    var project: Project?

    @OptionalField(key: "due_date")
    var dueDate: Date?

    /// The Sprint (`CONTEXT.md`) this Task is grouped into, if any — optional
    /// since a Project's use of Sprints is optional and a Task can be listed
    /// unscoped within its Project. Cleared automatically when the Task
    /// moves to a different Project than the one its Sprint belongs to
    /// (`TaskController.assignProject`).
    @OptionalParent(key: "sprint_id")
    var sprint: Sprint?

    /// The Course (`CONTEXT.md`) this Task belongs to, if any — the
    /// alternate container to `project` (ADR-0003). Cleared automatically
    /// whenever the Task is assigned a Project (`TaskController.assignProject`),
    /// the same way `project`/`sprint` are cleared when the Task is assigned
    /// a Course (`TaskController.assignCourse`).
    @OptionalParent(key: "course_id")
    var course: Course?

    init() {}

    init(
        id: UUID? = nil,
        title: String,
        notes: String? = nil,
        isComplete: Bool = false,
        projectID: UUID? = nil,
        dueDate: Date? = nil,
        sprintID: UUID? = nil,
        courseID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.isComplete = isComplete
        self.$project.id = projectID
        self.dueDate = dueDate
        self.$sprint.id = sprintID
        self.$course.id = courseID
    }
}
