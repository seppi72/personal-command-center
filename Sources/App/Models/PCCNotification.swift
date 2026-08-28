import Fluent
import Vapor

/// A surfaced item requiring the owner's attention (`CONTEXT.md`), stored
/// rather than live-computed so it can be dismissed and stay dismissed.
/// Points back at whatever triggered it via `sourceType`/`sourceID` — the
/// same open-ended plain-string pointer shape `AutomationLog` already uses
/// for its own `subjectType`/`subjectID`, chosen over a Fluent `@Enum` since
/// the set of source types will keep growing (an overdue Task/Project/Course
/// today, more later). Rows are created automatically by
/// `NotificationScanService` (ticket #47, an overdue-Deadline scan) and by
/// `CalendarSyncService` on an Automation Log failure (ticket #48) — this
/// model and `NotificationController` are just the shared storage and
/// read/dismiss surface underneath both.
///
/// Named `PCCNotification` in Swift only: an unqualified `Notification`
/// collides with Foundation's own `Notification`/`NotificationCenter` types,
/// pulled in transitively on this platform — the same kind of stdlib/
/// Foundation collision `PCCTask`/`PCCCategory` already sidestep this way.
/// The domain term "Notification" is what shows up everywhere that matters —
/// the `schema` (`notifications`), the JSON API, docs, and UI text.
final class PCCNotification: Model, @unchecked Sendable {
    static let schema = "notifications"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "source_type")
    var sourceType: String

    @Field(key: "source_id")
    var sourceID: UUID

    @Field(key: "message")
    var message: String

    @Field(key: "is_dismissed")
    var isDismissed: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    /// `createdAt` is nil only before a row is first saved
    /// (`@Timestamp(on: .create)`) — by the time a row round-trips through
    /// Fluent it's always set, so `.distantPast` here is unreachable in
    /// practice rather than a real fallback. Mirrors
    /// `AutomationLog.occurredAtOrDistantPast`.
    var createdAtOrDistantPast: Date {
        createdAt ?? .distantPast
    }

    init() {}

    init(id: UUID? = nil, sourceType: String, sourceID: UUID, message: String, isDismissed: Bool = false) {
        self.id = id
        self.sourceType = sourceType
        self.sourceID = sourceID
        self.message = message
        self.isDismissed = isDismissed
    }
}
