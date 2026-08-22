import Foundation

/// Holds the Personal Commitments screen's state and talks to the backend
/// through a `PersonalCommitmentsAPIClient` — kept separate from
/// `PersonalCommitmentsView` so the view stays a thin rendering of this
/// state (mirrors `ProjectsViewModel`'s split).
///
/// `ObservableObject` rather than the newer `@Observable` macro, since that
/// macro needs iOS 17/macOS 14 and this package targets iOS 16/macOS 13.
@MainActor
public final class PersonalCommitmentsViewModel: ObservableObject {
    @Published public private(set) var commitments: [PersonalCommitment] = []
    @Published public var errorMessage: String?
    @Published public private(set) var isLoading = false

    private let client: PersonalCommitmentsAPIClient

    public init(client: PersonalCommitmentsAPIClient) {
        self.client = client
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        await run(verb: "load") {
            commitments = try await client.listPersonalCommitments()
        }
    }

    public func createCommitment(_ values: PersonalCommitmentFormValues) async {
        await run(verb: "create") {
            commitments.append(try await client.createPersonalCommitment(values))
        }
    }

    public func updateCommitment(_ commitment: PersonalCommitment, with values: PersonalCommitmentFormValues) async {
        await run(verb: "update") {
            let updated = try await client.updatePersonalCommitment(id: commitment.id, values: values)
            if let index = commitments.firstIndex(where: { $0.id == updated.id }) {
                commitments[index] = updated
            }
        }
    }

    public func deleteCommitment(_ commitment: PersonalCommitment) async {
        await run(verb: "delete") {
            try await client.deletePersonalCommitment(id: commitment.id)
            commitments.removeAll { $0.id == commitment.id }
        }
    }

    /// Runs a mutation against `commitments`, keeping every method's
    /// success/failure handling (clear the error; on failure surface a
    /// message) in one shape instead of four copies.
    private func run(verb: String, _ operation: () async throws -> Void) async {
        do {
            try await operation()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't \(verb) Personal Commitment: \(error.localizedDescription)"
        }
    }
}
