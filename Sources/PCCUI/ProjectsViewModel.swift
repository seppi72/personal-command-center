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

    public func createProject(name: String) async {
        await run(verb: "create") {
            projects.append(try await client.createProject(name: name))
        }
    }

    public func renameProject(_ project: Project, to name: String) async {
        await run(verb: "rename") {
            let updated = try await client.updateProject(id: project.id, name: name)
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
