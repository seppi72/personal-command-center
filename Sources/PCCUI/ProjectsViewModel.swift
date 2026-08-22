import Foundation

/// Holds the Projects screen's state and talks to the backend through a
/// `ProjectsAPIClient`. Kept separate from `ProjectsView` so the view stays
/// a thin rendering of this state (mirrors the backend's
/// Controller/Service split).
///
/// `ObservableObject` rather than the newer `@Observable` macro, since that
/// macro needs iOS 17/macOS 14 and this package targets iOS 16/macOS 13.
@MainActor
public final class ProjectsViewModel: ObservableObject {
    @Published public private(set) var projects: [Project] = []
    @Published public var errorMessage: String?
    @Published public private(set) var isLoading = false

    private let client: ProjectsAPIClient

    public init(client: ProjectsAPIClient) {
        self.client = client
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        await run(verb: "load") {
            projects = try await client.listProjects()
        }
    }

    /// Creates a Project and, if `values.dueDate` is given, attaches it in a
    /// follow-up call — a Project is always created undated on the backend
    /// (`ProjectController.create`), so a Deadline is a separate write.
    public func createProject(_ values: ProjectFormValues) async {
        await run(verb: "create") {
            var created = try await client.createProject(name: values.name)
            if let dueDate = values.dueDate {
                created = try await client.setProjectDeadline(id: created.id, dueDate: dueDate)
            }
            projects.append(created)
        }
    }

    /// Renames a Project and, only if `values.dueDate` differs from
    /// `project`'s current one, updates its Deadline as a follow-up write —
    /// the same "write, then maybe update the rest" shape as `createProject`.
    public func updateProject(_ project: Project, with values: ProjectFormValues) async {
        await run(verb: "update") {
            var updated = try await client.updateProject(id: project.id, name: values.name)
            if values.dueDate != project.dueDate {
                updated = try await client.setProjectDeadline(id: project.id, dueDate: values.dueDate)
            }
            if let index = projects.firstIndex(where: { $0.id == updated.id }) {
                projects[index] = updated
            }
        }
    }

    public func deleteProject(_ project: Project) async {
        await run(verb: "delete") {
            try await client.deleteProject(id: project.id)
            projects.removeAll { $0.id == project.id }
        }
    }

    /// Runs a mutation against `projects`, keeping every method's
    /// success/failure handling (clear the error, re-sort by name; on
    /// failure surface a message) in one shape instead of four copies.
    private func run(verb: String, _ operation: () async throws -> Void) async {
        do {
            try await operation()
            projects.sort { $0.name < $1.name }
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't \(verb) Project: \(error.localizedDescription)"
        }
    }
}
