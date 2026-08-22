import Fluent
import Vapor

/// A read-only cache of a pulled external Calendar event (`CONTEXT.md`) —
/// kept as its own table, separate from `PersonalCommitment`, since these
/// rows are not owner-editable and are not Personal Commitments (spec #1's
/// schema, user story 22). Populated and kept current by
/// `CalendarSyncService.pull` (ticket #7); no controller writes to this
/// table — `MirroredCalendarEventController` only exposes `index`.
final class MirroredCalendarEvent: Model, @unchecked Sendable {
    static let schema = "mirrored_calendar_events"

    @ID(key: .id)
    var id: UUID?

    /// The external Calendar's own event id (its CalDAV UID) — what
    /// `CalendarSyncService.pull` upserts on, so a repeated pull converges
    /// to whatever the external Calendar currently has instead of
    /// duplicating a row per pull.
    @Field(key: "external_event_id")
    var externalEventID: String

    @Field(key: "title")
    var title: String

    @Field(key: "start_date")
    var startDate: Date

    @Field(key: "end_date")
    var endDate: Date

    /// When this row was last written by a pull — lets the owner (and a
    /// future staleness check) tell a freshly-synced mirror from one that
    /// hasn't heard from CalDAV in a while.
    @Field(key: "last_synced_at")
    var lastSyncedAt: Date

    init() {}

    init(
        id: UUID? = nil,
        externalEventID: String,
        title: String,
        startDate: Date,
        endDate: Date,
        lastSyncedAt: Date = Date()
    ) {
        self.id = id
        self.externalEventID = externalEventID
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.lastSyncedAt = lastSyncedAt
    }
}
