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

    /// When this Task was last marked complete — `nil` while incomplete, and
    /// cleared back to `nil` if marked incomplete again, so a Task
    /// re-completed later gets a fresh timestamp rather than keeping a stale
    /// one from a prior completion (`TaskController.setCompletion`). Backs
    /// the dashboard's on-time completion rate: whether this is on/before
    /// `dueDate`.
    @OptionalField(key: "completed_at")
    var completedAt: Date?

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

    /// `project`/`course` read together as one `TaskContainer` — see its
    /// doc comment for why they're bundled.
    var container: TaskContainer {
        if let projectID = $project.id { return .project(projectID) }
        if let courseID = $course.id { return .course(courseID) }
        return .none
    }

    /// Moves this Task to `container`, clearing whichever of Project/Course
    /// isn't the new one (ADR-0003's exclusivity) — the single place
    /// `TaskController.assignProject`/`assignCourse` both funnel through,
    /// replacing what used to be the same "clear the other side" logic
    /// written out twice. Also clears the Sprint whenever the Project
    /// changes (ticket #18: a Sprint is scoped to the Project it was
    /// created in for its lifetime), including when the Project is cleared
    /// by a Course assignment — `container`'s cases are mutually exclusive
    /// by construction, so there's no separate "did the Course change"
    /// check to make: a Task's Project only ever changes here by going to
    /// its new value, `nil`, or displaced by a Course.
    func setContainer(_ container: TaskContainer) {
        let previousProjectID = $project.id
        switch container {
        case .project(let id):
            $project.id = id
            $course.id = nil
        case .course(let id):
            $project.id = nil
            $course.id = id
        case .none:
            $project.id = nil
            $course.id = nil
        }
        if $project.id != previousProjectID {
            $sprint.id = nil
        }
    }
}
