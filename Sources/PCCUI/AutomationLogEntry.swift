import Foundation

/// Client-side mirror of the backend's `AutomationLogResponse` (ticket #8) —
/// one audit-trail record of an action the system took on its own
/// (`CONTEXT.md`), e.g. a CalDAV push/pull performed by `CalendarSyncService`.
public struct AutomationLogEntry: Codable, Identifiable, Equatable, Sendable {
    public enum Outcome: String, Codable, Equatable, Sendable {
        case success
        case failure
    }

    public let id: UUID
    public var actionType: String
    public var subjectType: String
    public var subjectID: UUID
    public var detail: String
    public var outcome: Outcome
    public var occurredAt: Date

    public init(
        id: UUID,
        actionType: String,
        subjectType: String,
        subjectID: UUID,
        detail: String,
        outcome: Outcome,
        occurredAt: Date
    ) {
        self.id = id
        self.actionType = actionType
        self.subjectType = subjectType
        self.subjectID = subjectID
        self.detail = detail
        self.outcome = outcome
        self.occurredAt = occurredAt
    }
}

/// Client-side mirror of the backend's `AutomationLogsResponse`: recent
/// entries plus the most recent sync failure, singled out so it isn't only
/// visible if the owner happens to scroll far enough down `entries` to find
/// it (this ticket's "surfaced clearly... rather than failing silently" AC).
public struct AutomationLogsPage: Codable, Equatable, Sendable {
    public var entries: [AutomationLogEntry]
    public var mostRecentFailure: AutomationLogEntry?

    public init(entries: [AutomationLogEntry], mostRecentFailure: AutomationLogEntry?) {
        self.entries = entries
        self.mostRecentFailure = mostRecentFailure
    }
}
