import Foundation

/// Client-side mirror of the backend's `PersonalCommitmentResponse` — a
/// recurring or scheduled personal obligation (`CONTEXT.md`), distinct from
/// a Task since it's scheduled/time-bound rather than completed.
public struct PersonalCommitment: Codable, Identifiable, Equatable, Sendable {
    /// Mirrors the backend's `PersonalCommitment.SyncStatus` — a real typed
    /// enum here too (not a bare `String`), so `PersonalCommitmentsView` can
    /// exhaustively switch over known cases instead of matching raw string
    /// literals against the server's JSON.
    public enum SyncStatus: String, Equatable, Sendable {
        case pending
        case synced
        case failed
    }

    public let id: UUID
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var recurrenceRule: String?

    /// Stored as the raw wire value; `syncStatus` maps an unrecognized one
    /// to `.pending` rather than failing to decode the whole Commitment —
    /// same fallback the backend's own `PersonalCommitment.syncStatus`
    /// getter uses, so client and server treat an unexpected value the same
    /// way.
    private var syncStatusRaw: String

    public var syncStatus: SyncStatus {
        SyncStatus(rawValue: syncStatusRaw) ?? .pending
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, startDate, endDate, recurrenceRule
        case syncStatusRaw = "syncStatus"
    }

    public init(
        id: UUID,
        title: String,
        startDate: Date,
        endDate: Date,
        recurrenceRule: String? = nil,
        syncStatus: SyncStatus = .pending
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.recurrenceRule = recurrenceRule
        self.syncStatusRaw = syncStatus.rawValue
    }
}
