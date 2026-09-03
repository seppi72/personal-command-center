import Foundation

/// Holds the Clients screen's state and talks to the backend through a
/// `ClientsAPIClient`. Kept separate from `ClientsView` so the view stays a
/// thin rendering of this state (mirrors `ProjectsViewModel`'s split).
///
/// `ObservableObject` rather than the newer `@Observable` macro, since that
/// macro needs iOS 17/macOS 14 and this package targets iOS 16/macOS 13.
@MainActor
public final class ClientsViewModel: ObservableObject {
    @Published public private(set) var clients: [PCCClient] = []
    /// Every Project across every Client, loaded alongside `clients` — the
    /// Clients screen shows each Client's own Projects directly on its card
    /// (`projects(for:)`), so this view model needs Project data it
    /// previously had no reason to hold.
    @Published public private(set) var projects: [Project] = []
    @Published public var errorMessage: String?
    @Published public private(set) var isLoading = false

    private let client: ClientsAPIClient
    private let projectsClient: ProjectsAPIClient

    public init(client: ClientsAPIClient, projectsClient: ProjectsAPIClient) {
        self.client = client
        self.projectsClient = projectsClient
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        await run(verb: "load") {
            async let loadedClients = client.listClients()
            async let loadedProjects = projectsClient.listProjects()
            clients = try await loadedClients
            projects = try await loadedProjects
        }
    }

    /// Every Project belonging to `client`, in whatever order the backend
    /// returned them — this screen's whole reason for holding `projects`
    /// at all.
    public func projects(for client: PCCClient) -> [Project] {
        projects.filter { $0.clientID == client.id }
    }

    public func createClient(name: String) async {
        await run(verb: "create") {
            clients.append(try await client.createClient(name: name))
        }
    }

    public func updateClient(_ existing: PCCClient, name: String) async {
        await run(verb: "update") {
            let updated = try await client.updateClient(id: existing.id, name: name)
            if let index = clients.firstIndex(where: { $0.id == updated.id }) {
                clients[index] = updated
            }
        }
    }

    public func deleteClient(_ existing: PCCClient) async {
        await run(verb: "delete") {
            try await client.deleteClient(id: existing.id)
            clients.removeAll { $0.id == existing.id }
        }
    }

    /// Runs a mutation against `clients`, keeping every method's
    /// success/failure handling (clear the error, re-sort by name; on
    /// failure surface a message) in one shape instead of four copies
    /// (mirrors `ProjectsViewModel.run`).
    private func run(verb: String, _ operation: () async throws -> Void) async {
        do {
            try await operation()
            clients.sort { $0.name < $1.name }
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't \(verb) Client: \(error.localizedDescription)"
        }
    }
}
