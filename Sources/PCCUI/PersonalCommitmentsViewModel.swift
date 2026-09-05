import Foundation

/// Holds the Personal Commitments screen's state and talks to the backend
/// through a `PersonalCommitmentsAPIClient`, plus a `CoursesAPIClient` to
/// populate the Course picker (ticket #56) — kept separate from
/// `PersonalCommitmentsView` so the view stays a thin rendering of this
/// state (mirrors `WorkViewModel`'s split).
///
/// Lists every Commitment; there is no Course-scoped variant. A per-Course
/// fetch existed for the Courses screen's "Meetings" section (ticket #56),
/// but issue #90 folded that screen into `SchoolViewModel`, which filters the
/// Commitments it already loaded rather than re-fetching one Course's at a
/// time, and issue #98 removed the unused scoping.
///
/// `ObservableObject` rather than the newer `@Observable` macro, since that
/// macro needs iOS 17/macOS 14 and this package targets iOS 16/macOS 13.
@MainActor
public final class PersonalCommitmentsViewModel: ObservableObject {
    @Published public private(set) var commitments: [PersonalCommitment] = []
    @Published public private(set) var courses: [Course] = []
    @Published public var errorMessage: String?
    @Published public private(set) var isLoading = false

    private let client: PersonalCommitmentsAPIClient
    private let coursesClient: CoursesAPIClient

    public init(client: PersonalCommitmentsAPIClient, coursesClient: CoursesAPIClient) {
        self.client = client
        self.coursesClient = coursesClient
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        await run(verb: "load") {
            async let loadedCommitments = client.listPersonalCommitments(courseID: nil)
            async let loadedCourses = coursesClient.listCourses()
            commitments = try await loadedCommitments
            courses = try await loadedCourses
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
            replace(updated)
        }
    }

    public func deleteCommitment(_ commitment: PersonalCommitment) async {
        await run(verb: "delete") {
            try await client.deletePersonalCommitment(id: commitment.id)
            commitments.removeAll { $0.id == commitment.id }
        }
    }

    /// Swaps the freshly-updated Commitment into `commitments` (mirrors
    /// `WorkViewModel.replace`).
    private func replace(_ updated: PersonalCommitment) {
        guard let index = commitments.firstIndex(where: { $0.id == updated.id }) else { return }
        commitments[index] = updated
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
