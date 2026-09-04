import Foundation

/// Holds one Project's Sprints screen state and talks to the backend
/// through a `SprintsAPIClient`. Scoped to a single `projectID` given at
/// `init` — a Sprint has no meaning outside a Project, so unlike
/// `WorkViewModel` there's no unscoped "all Sprints" list. Kept separate
/// from its view so the view stays a thin rendering of this state (mirrors
/// `WorkViewModel`'s split).
///
/// `ObservableObject` rather than the newer `@Observable` macro, since that
/// macro needs iOS 17/macOS 14 and this package targets iOS 16/macOS 13.
@MainActor
public final class SprintsViewModel: ObservableObject {
    @Published public private(set) var sprints: [Sprint] = []
    @Published public var errorMessage: String?
    @Published public private(set) var isLoading = false

    private let client: SprintsAPIClient
    private let projectID: UUID

    public init(client: SprintsAPIClient, projectID: UUID) {
        self.client = client
        self.projectID = projectID
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        await run(verb: "load") {
            sprints = try await client.listSprints(projectID: projectID)
        }
    }

    public func createSprint(_ values: SprintFormValues) async {
        await run(verb: "create") {
            sprints.append(
                try await client.createSprint(
                    projectID: projectID,
                    name: values.name,
                    startDate: values.startDate,
                    endDate: values.endDate
                )
            )
        }
    }

    public func updateSprint(_ existing: Sprint, with values: SprintFormValues) async {
        await run(verb: "update") {
            let updated = try await client.updateSprint(
                id: existing.id,
                name: values.name,
                startDate: values.startDate,
                endDate: values.endDate
            )
            if let index = sprints.firstIndex(where: { $0.id == updated.id }) {
                sprints[index] = updated
            }
        }
    }

    public func deleteSprint(_ existing: Sprint) async {
        await run(verb: "delete") {
            try await client.deleteSprint(id: existing.id)
            sprints.removeAll { $0.id == existing.id }
        }
    }

    /// Runs a mutation against `sprints`, keeping every method's
    /// success/failure handling (clear the error, re-sort by start date; on
    /// failure surface a message) in one shape instead of four copies
    /// (mirrors `WorkViewModel.run`).
    private func run(verb: String, _ operation: () async throws -> Void) async {
        do {
            try await operation()
            sprints.sort { $0.startDate < $1.startDate }
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't \(verb) Sprint: \(error.localizedDescription)"
        }
    }
}
