import Foundation

/// Holds the Tasks screen's state and talks to the backend through a
/// `TasksAPIClient`, plus a `ProjectsAPIClient`/`CoursesAPIClient` to
/// populate the Project/Course pickers — kept separate from `CourseDetailView` so
/// the view stays a thin rendering of this state (mirrors `WorkViewModel`'s
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
            if let kind = values.kind {
                created = try await tasksClient.setTaskKind(id: created.id, kind: kind)
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
            if values.kind != task.kind {
                updated = try await tasksClient.setTaskKind(id: task.id, kind: values.kind)
            }
            replace(updated)
        }
    }

    /// Reconciles `task`'s Project/Course with `values`' desired ones and
    /// returns the result — the requested `TaskContainer` decides which
    /// endpoint to call, since either one clears the other side already
    /// (ADR-0003); requesting `.none` (both cleared) falls back to whichever
    /// one `task` actually had. Only called when `updateTask` has already
    /// confirmed one of the two changed.
    private func reassignContainer(of task: PCCTask, to values: TaskFormValues) async throws -> PCCTask {
        let requested = TaskContainer(projectID: values.projectID, courseID: values.courseID)
        let target = requested == .none
            ? TaskContainer(projectID: task.projectID, courseID: task.courseID)
            : requested
        switch target {
        case .course(let id):
            return try await tasksClient.assignTaskCourse(id: task.id, courseID: id)
        case .project(let id):
            return try await tasksClient.assignTaskProject(id: task.id, projectID: id)
        case .none:
            return try await tasksClient.assignTaskProject(id: task.id, projectID: nil)
        }
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

    /// `scopedProjectID`/`scopedCourseID` read together as one
    /// `TaskContainer` — the screen is scoped to a Project, a Course, or (both
    /// `nil`) not scoped at all, the same three-way shape a Task's own
    /// container has.
    private var scope: TaskContainer {
        TaskContainer(projectID: scopedProjectID, courseID: scopedCourseID)
    }

    /// Whether `task` belongs where this screen is scoped — always `true`
    /// for the unscoped, top-level Tasks screen.
    private func matchesScope(_ task: PCCTask) -> Bool {
        switch scope {
        case .none: return true
        case .project(let id): return task.projectID == id
        case .course(let id): return task.courseID == id
        }
    }

    /// Whether `task` is overdue: has a due date, isn't complete, and that
    /// due date has passed as of `referenceDate`. Pure and `static` — moved
    /// off the since-deleted `TasksView` (issue #68) so it's unit-testable at this package's
    /// one pure-logic test seam (`PCCUITests`) without needing a whole
    /// `TasksViewModel` instance wired up with API clients. `referenceDate`
    /// defaults to `Date()` for every real call site; tests pass a fixed
    /// date instead so the result doesn't depend on when they happen to run.
    public static nonisolated func isOverdue(_ task: PCCTask, referenceDate: Date = Date()) -> Bool {
        guard let dueDate = task.dueDate, !task.isComplete else { return false }
        return dueDate < referenceDate
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
