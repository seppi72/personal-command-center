import Fluent
import Vapor

/// An audit-trail record of an action the system took on its own
/// (`CONTEXT.md`) — e.g. a CalDAV push — kept so the automation can be
/// trusted and debugged rather than re-checked by hand. Written by
/// `CalendarSyncService`; a read/listing endpoint is ticket #8's job, not
/// this ticket's.
final class AutomationLog: Model, @unchecked Sendable {
    static let schema = "automation_logs"

    /// Stored as a plain `String`, same tradeoff as
    /// `PersonalCommitment.SyncStatus` — no Fluent `@Enum` precedent exists
    /// yet in this codebase.
    enum Outcome: String {
        case success
        case failure
    }

    @ID(key: .id)
    var id: UUID?

    /// e.g. `"personal_commitment.create"` — dotted `<subject>.<verb>`, not
    /// its own enum, since the set of action types will keep growing as
    /// more of spec #1's automation lands (Calendar pull, later domains).
    @Field(key: "action_type")
    var actionType: String

    @Field(key: "subject_type")
    var subjectType: String

    @Field(key: "subject_id")
    var subjectID: UUID

    @Field(key: "detail")
    var detail: String

    @Field(key: "outcome")
    private var outcomeRaw: String

    var outcome: Outcome {
        get { Outcome(rawValue: outcomeRaw) ?? .failure }
        set { outcomeRaw = newValue.rawValue }
    }

    @Timestamp(key: "occurred_at", on: .create)
    var occurredAt: Date?

    init() {}

    init(id: UUID? = nil, actionType: String, subjectType: String, subjectID: UUID, detail: String, outcome: Outcome) {
        self.id = id
        self.actionType = actionType
        self.subjectType = subjectType
        self.subjectID = subjectID
        self.detail = detail
        self.outcomeRaw = outcome.rawValue
    }
}
