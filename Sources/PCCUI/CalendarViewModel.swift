import Foundation

/// Holds the combined Calendar screen's state (ticket #7): owner-created
/// Personal Commitments and read-only mirrored external Calendar events,
/// merged into one Deadline-proximity-style sorted list (mirrors
/// `DeadlinesViewModel`'s "flatten two sources into one sorted list"
/// shape). Commitment create/edit/delete go through this view model too —
/// unlike `DeadlinesViewModel`, which is read-only end to end, this screen
/// owns the one kind of row (`.commitment`) that's actually editable.
///
/// `ObservableObject` rather than the newer `@Observable` macro, since that
/// macro needs iOS 17/macOS 14 and this package targets iOS 16/macOS 13.
@MainActor
public final class CalendarViewModel: ObservableObject {
    @Published public private(set) var entries: [CalendarEntry] = []
    @Published public private(set) var courses: [Course] = []
    @Published public var errorMessage: String?
    @Published public private(set) var isLoading = false

    private let commitmentsClient: PersonalCommitmentsAPIClient
    private let mirroredEventsClient: MirroredCalendarEventsAPIClient
    private let coursesClient: CoursesAPIClient

    public init(
        commitmentsClient: PersonalCommitmentsAPIClient,
        mirroredEventsClient: MirroredCalendarEventsAPIClient,
        coursesClient: CoursesAPIClient
    ) {
        self.commitmentsClient = commitmentsClient
        self.mirroredEventsClient = mirroredEventsClient
        self.coursesClient = coursesClient
    }

    /// Loads all three sources concurrently and merges the two calendar
    /// ones into one list sorted by start time — the backend has no
    /// combined endpoint of its own (`/v1/personal-commitments` and
    /// `/v1/calendar-events` are separate), so the merge happens here,
    /// client-side. `courses` sources the Commitment form's Course picker
    /// (ticket #56) — the same reason `TasksViewModel`/`TimeEntriesViewModel`
    /// each load their own copy of it.
    public func load() async {
        isLoading = true
        defer { isLoading = false }
        await run(verb: "load") {
            async let commitments = commitmentsClient.listPersonalCommitments(courseID: nil)
            async let mirroredEvents = mirroredEventsClient.listMirroredCalendarEvents()
            async let loadedCourses = coursesClient.listCourses()
            let (loadedCommitments, loadedMirroredEvents) = try await (commitments, mirroredEvents)
            entries = merged(commitments: loadedCommitments, mirroredEvents: loadedMirroredEvents)
            courses = try await loadedCourses
        }
    }

    public func createCommitment(_ values: PersonalCommitmentFormValues) async {
        await run(verb: "create") {
            let created = try await commitmentsClient.createPersonalCommitment(values)
            upsert(.commitment(created))
        }
    }

    public func updateCommitment(_ commitment: PersonalCommitment, with values: PersonalCommitmentFormValues) async {
        await run(verb: "update") {
            let updated = try await commitmentsClient.updatePersonalCommitment(id: commitment.id, values: values)
            upsert(.commitment(updated))
        }
    }

    public func deleteCommitment(_ commitment: PersonalCommitment) async {
        await run(verb: "delete") {
            try await commitmentsClient.deletePersonalCommitment(id: commitment.id)
            entries.removeAll { $0.id == CalendarEntry.commitment(commitment).id }
        }
    }

    private func merged(commitments: [PersonalCommitment], mirroredEvents: [MirroredCalendarEvent]) -> [CalendarEntry] {
        (commitments.map(CalendarEntry.commitment) + mirroredEvents.map(CalendarEntry.mirroredEvent))
            .sorted { $0.startDate < $1.startDate }
    }

    private func upsert(_ entry: CalendarEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        entries.sort { $0.startDate < $1.startDate }
    }

    /// Runs a mutation, keeping every method's success/failure handling
    /// (clear the error; on failure surface a message) in one shape instead
    /// of several copies (mirrors `PersonalCommitmentsViewModel.run`).
    private func run(verb: String, _ operation: () async throws -> Void) async {
        do {
            try await operation()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't \(verb) Calendar: \(error.localizedDescription)"
        }
    }
}
