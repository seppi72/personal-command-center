import Foundation

/// Holds the Tasks screen's state and talks to the backend through a
/// `TasksAPIClient`, plus a `ProjectsAPIClient` to populate the Project
/// picker — kept separate from `TasksView` so the view stays a thin
/// rendering of this state (mirrors `ProjectsViewModel`'s split).
///
/// `ObservableObject` rather than the newer `@Observable` macro, since that
/// macro needs iOS 17/macOS 14 and this package targets iOS 16/macOS 13.
@MainActor
public final class TasksViewModel: ObservableObject {
    @Published public private(set) var tasks: [PCCTask] = []
    @Published public private(set) var projects: [Project] = []
    @Published public var errorMessage: String?
    @Published public private(set) var isLoading = false

    private let tasksClient: TasksAPIClient
    private let projectsClient: ProjectsAPIClient

    /// When set, this screen is scoped to one Project (`GET
    /// /v1/tasks?projectID=`) rather than listing every Task.
    private let scopedProjectID: UUID?

    public init(tasksClient: TasksAPIClient, projectsClient: ProjectsAPIClient, scopedProjectID: UUID? = nil) {
        self.tasksClient = tasksClient
        self.projectsClient = projectsClient
        self.scopedProjectID = scopedProjectID
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        await run(verb: "load") {
            async let loadedTasks = tasksClient.listTasks(projectID: scopedProjectID)
            async let loadedProjects = projectsClient.listProjects()
            tasks = try await loadedTasks
            projects = try await loadedProjects
        }
    }

    /// Creates a Task and, if `values.projectID` is given, assigns it in a
    /// second call — a Task is always created Project-less on the backend
    /// (`TaskController.create`), so assignment is a follow-up write.
    public func createTask(_ values: TaskFormValues) async {
        await run(verb: "create") {
            var created = try await tasksClient.createTask(title: values.title, notes: values.notes)
            if let projectID = values.projectID {
                created = try await tasksClient.assignTaskProject(id: created.id, projectID: projectID)
            }
            if scopedProjectID == nil || created.projectID == scopedProjectID {
                tasks.append(created)
            }
        }
    }

    /// Edits a Task's title/notes and, only if `values.projectID` differs
    /// from `task`'s current one, reassigns its Project as a second write —
    /// the same "write, then maybe reassign" shape as `createTask`, kept
    /// here rather than left for the caller to decide.
    public func updateTask(_ task: PCCTask, with values: TaskFormValues) async {
        await run(verb: "update") {
            var updated = try await tasksClient.updateTask(id: task.id, title: values.title, notes: values.notes)
            if values.projectID != task.projectID {
                updated = try await tasksClient.assignTaskProject(id: task.id, projectID: values.projectID)
            }
            replace(updated)
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

    /// Swaps the freshly-updated Task into `tasks`, dropping it when scoped
    /// to a Project it no longer belongs to.
    private func replace(_ updated: PCCTask) {
        guard let index = tasks.firstIndex(where: { $0.id == updated.id }) else { return }
        if let scopedProjectID, updated.projectID != scopedProjectID {
            tasks.remove(at: index)
        } else {
            tasks[index] = updated
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
