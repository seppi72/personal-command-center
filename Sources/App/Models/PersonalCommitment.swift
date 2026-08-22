import Fluent
import Vapor

/// A recurring or scheduled personal obligation (`CONTEXT.md`) — distinct
/// from a Task, since it's scheduled/time-bound rather than completed.
/// Canonical (`CONTEXT.md`): the Command Center owns this data and pushes
/// it out to the external Calendar via CalDAV (ADR-0002), rather than
/// mirroring an external source. Pulling existing external events *in* is
/// `MirroredCalendarEvent`'s job (ticket #7), not this model's.
final class PersonalCommitment: Model, @unchecked Sendable {
    static let schema = "personal_commitments"

    /// Stored as a plain `String` (like every other field in this codebase
    /// so far — no Fluent `@Enum` precedent exists yet) rather than a typed
    /// Fluent field, with `SyncStatus` giving call sites type safety without
    /// committing to Fluent's native-enum machinery for just one field.
    enum SyncStatus: String {
        /// Written but not yet pushed (a transient state between the
        /// initial save and the first `CalendarSyncService.push` call).
        case pending
        case synced
        case failed
    }

    @ID(key: .id)
    var id: UUID?

    @Field(key: "title")
    var title: String

    @Field(key: "start_date")
    var startDate: Date

    @Field(key: "end_date")
    var endDate: Date

    @OptionalField(key: "recurrence_rule")
    var recurrenceRule: String?

    /// The CalDAV UID this Commitment is pushed under, and (per
    /// `ICloudCalDAVClient`) the `.ics` resource name at the configured
    /// calendar URL. Assigned once, at creation — before the first push —
    /// so every push (create, edit) and the eventual delete all target the
    /// same stable resource.
    @Field(key: "external_event_id")
    var externalEventID: String

    @Field(key: "sync_status")
    private var syncStatusRaw: String

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }

    init() {}

    init(
        id: UUID? = nil,
        title: String,
        startDate: Date,
        endDate: Date,
        recurrenceRule: String? = nil,
        externalEventID: String? = nil,
        syncStatus: SyncStatus = .pending
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.recurrenceRule = recurrenceRule
        self.externalEventID = externalEventID ?? UUID().uuidString
        self.syncStatusRaw = syncStatus.rawValue
    }
}
