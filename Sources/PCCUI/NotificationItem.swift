import Foundation

/// Client-side mirror of the backend's `NotificationResponse` (ticket #46) —
/// one surfaced item requiring the owner's attention (`CONTEXT.md`), pointing
/// back at whatever triggered it via `sourceType`/`sourceID`.
public struct NotificationItem: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var sourceType: String
    public var sourceID: UUID
    public var message: String
    public var isDismissed: Bool
    public var createdAt: Date

    public init(
        id: UUID,
        sourceType: String,
        sourceID: UUID,
        message: String,
        isDismissed: Bool,
        createdAt: Date
    ) {
        self.id = id
        self.sourceType = sourceType
        self.sourceID = sourceID
        self.message = message
        self.isDismissed = isDismissed
        self.createdAt = createdAt
    }
}
