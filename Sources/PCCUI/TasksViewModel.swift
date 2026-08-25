import Foundation

/// Holds the Tasks screen's state and talks to the backend through a
/// `TasksAPIClient`, plus a `ProjectsAPIClient`/`CoursesAPIClient` to
/// populate the Project/Course pickers — kept separate from `TasksView` so
/// the view stays a thin rendering of this state (mirrors `ProjectsViewModel`'s
/// split).
///
/// `ObservableObject` rather than the newer `@Observable` macro, since that
/// macro needs iOS 17/macOS 14 and this package targets iOS 16/macOS 13.
@MainActor
public final class TasksViewModel: ObservableObject {
    @Published public private(set) var tasks: [PCCTask] = []
    @Published public private(set) var projects: [Project] = []
    @Published public private(set) var courses: [Course] = []
    @Published public var errorMessage: String?
    @Published public private(set) var isLoading = false

    private let tasksClient: TasksAPIClient
    private let projectsClient: ProjectsAPIClient
    private let coursesClient: CoursesAPIClient

    /// When set, this screen is scoped to one Project (`GET
    /// /v1/tasks?projectID=`) rather than listing every Task. Mutually
    /// exclusive with `scopedCourseID` in practice — a screen is embedded in
    /// at most one of a Project's or a Course's detail flow — though nothing
    /// stops both being `nil` for the unscoped, top-level Tasks screen.
    private let scopedProjectID: UUID?

    /// When set, this screen is scoped to one Course (`GET
    /// /v1/tasks?courseID=`) rather than listing every Task — the Course
    /// detail flow's counterpart to `scopedProjectID` (ticket #20).
    private let scopedCourseID: UUID?

    public init(
        tasksClient: TasksAPIClient,
        projectsClient: ProjectsAPIClient,
        coursesClient: CoursesAPIClient,
        scopedProjectID: UUID? = nil,
        scopedCourseID: UUID? = nil
    ) {
        self.tasksClient = tasksClient
        self.projectsClient = projectsClient
        self.coursesClient = coursesClient
        self.scopedProjectID = scopedProjectID
        self.scopedCourseID = scopedCourseID
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        await run(verb: "load") {
            async let loadedTasks = tasksClient.listTasks(projectID: scopedProjectID, courseID: scopedCourseID)
            async let loadedProjects = projectsClient.listProjects()
            async let loadedCourses = coursesClient.listCourses()
            tasks = try await loadedTasks
            projects = try await loadedProjects
            courses = try await loadedCourses
        }
    }

    /// Creates a Task and, if `values.courseID`/`values.projectID`/
    /// `values.dueDate` is given, assigns/attaches it in follow-up calls — a
    /// Task is always created Project-less and Course-less on the backend
    /// (`TaskController.create`), so each is a separate write. `courseID`
    /// takes priority over `projectID` when both are somehow set — the form
    /// itself keeps them mutually exclusive (ADR-0003), but the assignment
    /// endpoints also enforce it server-side either way.
    public func createTask(_ values: TaskFormValues) async {
        await run(verb: "create") {
            var created = try await tasksClient.createTask(title: values.title, notes: values.notes)
            if let courseID = values.courseID {
                created = try await tasksClient.assignTaskCourse(id: created.id, courseID: courseID)
            } else if let projectID = values.projectID {
                created = try await tasksClient.assignTaskProject(id: created.id, projectID: projectID)
            }
            if let dueDate = values.dueDate {
                created = try await tasksClient.setTaskDeadline(id: created.id, dueDate: dueDate)
            }
            if matchesScope(created) {
                tasks.append(created)
            }
        }
    }

    /// Edits a Task's title/notes and, only where its Project/Course/Deadline
    /// differs from `task`'s current one, reassigns it as a follow-up write —
    /// the same "write, then maybe update the rest" shape as `createTask`,
    /// kept here rather than left for the caller to decide. See
    /// `reassignContainer(of:to:)` for how a Project/Course change resolves
    /// to a single assignment call.
    public func updateTask(_ task: PCCTask, with values: TaskFormValues) async {
        await run(verb: "update") {
            var updated = try await tasksClient.updateTask(id: task.id, title: values.title, notes: values.notes)
            if values.projectID != task.projectID || values.courseID != task.courseID {
                updated = try await reassignContainer(of: task, to: values)
            }
            if values.dueDate != task.dueDate {
                updated = try await tasksClient.setTaskDeadline(id: task.id, dueDate: values.dueDate)
            }
            replace(updated)
        }
    }

    /// Reconciles `task`'s Project/Course with `values`' desired ones and
    /// returns the result — the new, non-nil target decides which endpoint to
    /// call, since either one clears the other side already (ADR-0003);
    /// clearing both back to Project-less/Course-less falls back to whichever
    /// one `task` actually had. Only called when `updateTask` has already
    /// confirmed one of the two changed.
    private func reassignContainer(of task: PCCTask, to values: TaskFormValues) async throws -> PCCTask {
        if let courseID = values.courseID {
            return try await tasksClient.assignTaskCourse(id: task.id, courseID: courseID)
        }
        if let projectID = values.projectID {
            return try await tasksClient.assignTaskProject(id: task.id, projectID: projectID)
        }
        if task.courseID != nil {
            return try await tasksClient.assignTaskCourse(id: task.id, courseID: nil)
        }
        return try await tasksClient.assignTaskProject(id: task.id, projectID: nil)
    }

    public func deleteTask(_ task: PCCTask) async {
        await run(verb: "delete") {
            try await tasksClient.deleteTask(id: task.id)
            tasks.removeAll { $0.id == task.id }
        }
    }

    public func setCompletion(_ task: PCCTask, isComplete: Bool) async {
        await run(verb: "update") {
            replace(try await tasksClient.setTaskCompletion(id: task.id, isComplete: isComplete))
        }
    }

    /// Whether `task` belongs where this screen is scoped — always `true`
    /// for the unscoped, top-level Tasks screen (both scopes `nil`).
    private func matchesScope(_ task: PCCTask) -> Bool {
        if let scopedProjectID, task.projectID != scopedProjectID { return false }
        if let scopedCourseID, task.courseID != scopedCourseID { return false }
        return true
    }

    /// Swaps the freshly-updated Task into `tasks`, dropping it when scoped
    /// to a Project/Course it no longer belongs to.
    private func replace(_ updated: PCCTask) {
        guard let index = tasks.firstIndex(where: { $0.id == updated.id }) else { return }
        if matchesScope(updated) {
            tasks[index] = updated
        } else {
            tasks.remove(at: index)
        }
    }

    /// Runs a mutation against `tasks`, keeping every method's
    /// success/failure handling (clear the error; on failure surface a
    /// message) in one shape instead of many copies.
    private func run(verb: String, _ operation: () async throws -> Void) async {
        do {
            try await operation()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't \(verb) Task: \(error.localizedDescription)"
        }
    }
}
