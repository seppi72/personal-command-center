import Foundation

/// Holds the Automation Log screen's state (ticket #8) and talks to the
/// backend through an `AutomationLogsAPIClient` — kept separate from
/// `AutomationLogView` so the view stays a thin rendering of this state
/// (mirrors `DeadlinesViewModel`'s split). Read-only end to end: nothing on
/// this screen is owner-editable.
///
/// `ObservableObject` rather than the newer `@Observable` macro, since that
/// macro needs iOS 17/macOS 14 and this package targets iOS 16/macOS 13.
@MainActor
public final class AutomationLogViewModel: ObservableObject {
    @Published public private(set) var entries: [AutomationLogEntry] = []
    @Published public private(set) var mostRecentFailure: AutomationLogEntry?
    @Published public var errorMessage: String?
    @Published public private(set) var isLoading = false

    private let client: AutomationLogsAPIClient

    public init(client: AutomationLogsAPIClient) {
        self.client = client
    }

    /// The backend already orders `entries` most-recent-first and computes
    /// `mostRecentFailure` itself (`AutomationLogController.index`) — this
    /// just fetches and stores that shape as-is.
    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await client.listAutomationLogs()
            entries = page.entries
            mostRecentFailure = page.mostRecentFailure
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load the Automation Log: \(error.localizedDescription)"
        }
    }
}
