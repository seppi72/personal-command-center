import Foundation

/// Holds the Personal Commitments screen's state and talks to the backend
/// through a `PersonalCommitmentsAPIClient`, plus a `CoursesAPIClient` to
/// populate the Course picker (ticket #56) — kept separate from
/// `PersonalCommitmentsView` so the view stays a thin rendering of this
/// state (mirrors `ProjectsViewModel`'s split).
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

    /// When set, this screen is scoped to one Course (`GET
    /// /v1/personal-commitments?courseID=`) rather than listing every
    /// Commitment — `CourseDetailView`'s "Meetings" section (ticket #56),
    /// the same scoping shape `TasksViewModel.scopedCourseID` already has.
    private let scopedCourseID: UUID?

    public init(client: PersonalCommitmentsAPIClient, coursesClient: CoursesAPIClient, scopedCourseID: UUID? = nil) {
        self.client = client
        self.coursesClient = coursesClient
        self.scopedCourseID = scopedCourseID
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        await run(verb: "load") {
            async let loadedCommitments = client.listPersonalCommitments(courseID: scopedCourseID)
            async let loadedCourses = coursesClient.listCourses()
            commitments = try await loadedCommitments
            courses = try await loadedCourses
        }
    }

    public func createCommitment(_ values: PersonalCommitmentFormValues) async {
        await run(verb: "create") {
            let created = try await client.createPersonalCommitment(values)
            if matchesScope(created) {
                commitments.append(created)
            }
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

    /// Whether `commitment` belongs where this screen is scoped — always
    /// `true` for the unscoped, top-level Personal Commitments screen.
    private func matchesScope(_ commitment: PersonalCommitment) -> Bool {
        guard let scopedCourseID else { return true }
        return commitment.courseID == scopedCourseID
    }

    /// Swaps the freshly-updated Commitment into `commitments`, dropping it
    /// when scoped to a Course it no longer belongs to (mirrors
    /// `TasksViewModel.replace`).
    private func replace(_ updated: PersonalCommitment) {
        guard let index = commitments.firstIndex(where: { $0.id == updated.id }) else { return }
        if matchesScope(updated) {
            commitments[index] = updated
        } else {
            commitments.remove(at: index)
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
