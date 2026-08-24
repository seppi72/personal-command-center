import Foundation

/// Client-side mirror of the backend's `MirroredCalendarEventResponse` — a
/// read-only cache of a pulled external Calendar event (`CONTEXT.md`),
/// distinct from a `PersonalCommitment`: not owner-created, and not
/// editable through the Command Center (spec #1, user story 22).
public struct MirroredCalendarEvent: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var lastSyncedAt: Date

    public init(id: UUID, title: String, startDate: Date, endDate: Date, lastSyncedAt: Date) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.lastSyncedAt = lastSyncedAt
    }
}
