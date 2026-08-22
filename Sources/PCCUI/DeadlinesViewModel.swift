import Foundation

/// Holds the Deadlines screen's state and talks to the backend through a
/// `DeadlinesAPIClient` — kept separate from `DeadlinesView` so the view
/// stays a thin rendering of this state (mirrors `ProjectsViewModel`'s
/// split). Read-only: setting/clearing a Deadline happens on the Tasks and
/// Projects screens, not here — see `TasksViewModel`/`ProjectsViewModel`.
///
/// `ObservableObject` rather than the newer `@Observable` macro, since that
/// macro needs iOS 17/macOS 14 and this package targets iOS 16/macOS 13.
@MainActor
public final class DeadlinesViewModel: ObservableObject {
    @Published public private(set) var items: [DeadlineItem] = []
    @Published public var errorMessage: String?
    @Published public private(set) var isLoading = false

    private let client: DeadlinesAPIClient

    public init(client: DeadlinesAPIClient) {
        self.client = client
    }

    /// The backend already orders `items` by Deadline proximity with undated
    /// items included (`DeadlineController.index`) — this just fetches and
    /// stores that order as-is.
    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await client.listDeadlines()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load Deadlines: \(error.localizedDescription)"
        }
    }
}
