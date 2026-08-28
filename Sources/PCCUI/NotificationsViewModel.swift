import Foundation

/// Holds the Notifications screen's state (ticket #46) and talks to the
/// backend through a `NotificationsAPIClient` — kept separate from
/// `NotificationsView` so the view stays a thin rendering of this state
/// (mirrors `AutomationLogViewModel`'s split).
///
/// `ObservableObject` rather than the newer `@Observable` macro, since that
/// macro needs iOS 17/macOS 14 and this package targets iOS 16/macOS 13.
@MainActor
public final class NotificationsViewModel: ObservableObject {
    @Published public private(set) var notifications: [NotificationItem] = []
    @Published public var errorMessage: String?
    @Published public private(set) var isLoading = false

    private let client: NotificationsAPIClient

    public init(client: NotificationsAPIClient) {
        self.client = client
    }

    /// The backend already filters to undismissed rows and orders them
    /// newest-first (`NotificationController.index`) — this just fetches and
    /// stores that shape as-is.
    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            notifications = try await client.listNotifications()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load Notifications: \(error.localizedDescription)"
        }
    }

    /// Dismisses a Notification and drops it from `notifications` locally
    /// rather than re-fetching the whole list — the backend's own `index`
    /// would exclude it too (it filters to undismissed rows) but there's no
    /// need to round-trip again just to learn that.
    public func dismiss(_ notification: NotificationItem) async {
        do {
            _ = try await client.dismissNotification(id: notification.id)
            notifications.removeAll { $0.id == notification.id }
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't dismiss Notification: \(error.localizedDescription)"
        }
    }
}
