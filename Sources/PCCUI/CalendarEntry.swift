import Foundation

/// One row of the combined Calendar screen (ticket #7): either an
/// owner-created, editable `PersonalCommitment` or a read-only
/// `MirroredCalendarEvent` pulled from the external Calendar — the same
/// distinction spec #1's user story 22 asks the combined view to make
/// visible. A closed enum rather than a shared protocol, since
/// `CalendarViewModel`/`CalendarView` need to exhaustively branch on which
/// kind a row is (editable vs. not), not just read common fields off it.
public enum CalendarEntry: Identifiable, Equatable, Sendable {
    case commitment(PersonalCommitment)
    case mirroredEvent(MirroredCalendarEvent)

    /// Prefixed per case so a Commitment and a mirrored event that
    /// (implausibly) share a raw UUID never collide as the same row.
    public var id: String {
        switch self {
        case .commitment(let commitment):
            return "commitment-\(commitment.id)"
        case .mirroredEvent(let event):
            return "mirrored-\(event.id)"
        }
    }

    public var title: String {
        switch self {
        case .commitment(let commitment): return commitment.title
        case .mirroredEvent(let event): return event.title
        }
    }

    public var startDate: Date {
        switch self {
        case .commitment(let commitment): return commitment.startDate
        case .mirroredEvent(let event): return event.startDate
        }
    }

    public var endDate: Date {
        switch self {
        case .commitment(let commitment): return commitment.endDate
        case .mirroredEvent(let event): return event.endDate
        }
    }

    /// Whether this row can be edited through the Command Center — true
    /// for an owner-created Personal Commitment, false for a mirrored
    /// external Calendar event (spec #1, user story 22).
    public var isEditable: Bool {
        if case .commitment = self { return true }
        return false
    }
}
