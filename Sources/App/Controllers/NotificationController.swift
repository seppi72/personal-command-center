import Fluent
import Vapor

struct NotificationResponse: Content {
    let id: UUID
    let sourceType: String
    let sourceID: UUID
    let message: String
    let isDismissed: Bool
    let createdAt: Date

    init(_ notification: PCCNotification) throws {
        self.id = try notification.requireID()
        self.sourceType = notification.sourceType
        self.sourceID = notification.sourceID
        self.message = notification.message
        self.isDismissed = notification.isDismissed
        self.createdAt = notification.createdAtOrDistantPast
    }
}

/// The owner's "needs you" queue (`CONTEXT.md`'s Notification entry,
/// ticket #46): list what's currently open, and dismiss items from it.
/// Nothing here creates a `PCCNotification` — that's tickets #47/#48's
/// automated sourcing job; tests and manual verification insert rows
/// directly, the same way ticket #36 (Account CRUD) demoed Balance before
/// any Transaction existed to generate one. No `DELETE` route — a dismissed
/// row is never hard-deleted, kept for history the same way `AutomationLog`
/// entries are.
struct NotificationController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let notifications = routes.grouped("notifications")
        notifications.get(use: index)
        notifications.group(":notificationID") { notification in
            notification.post("dismiss", use: dismiss)
        }
    }

    /// Only undismissed rows, newest-first — a dismissed Notification is no
    /// longer something that "needs" the owner, so it drops out of this view
    /// entirely rather than showing crossed-out (it's still queryable via
    /// direct database access for history, just not through this endpoint).
    func index(req: Request) async throws -> [NotificationResponse] {
        let open = try await PCCNotification.query(on: req.db)
            .filter(\.$isDismissed == false)
            .all()
        let sorted = open.sorted { $0.createdAtOrDistantPast > $1.createdAtOrDistantPast }
        return try sorted.map(NotificationResponse.init)
    }

    /// Idempotent: dismissing an already-dismissed row succeeds as a no-op
    /// rather than erroring, since the caller's intent ("this should be
    /// dismissed") is already satisfied.
    func dismiss(req: Request) async throws -> NotificationResponse {
        guard let notification = try await findNotification(req: req) else {
            throw Abort(.notFound)
        }
        notification.isDismissed = true
        try await notification.save(on: req.db)
        return try NotificationResponse(notification)
    }

    private func findNotification(req: Request) async throws -> PCCNotification? {
        guard let id = req.parameters.get("notificationID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        return try await PCCNotification.find(id, on: req.db)
    }
}
