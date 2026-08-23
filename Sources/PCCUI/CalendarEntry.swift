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

    /// What every row displays, regardless of which case it came from —
    /// computed once per switch in `fields`, so `id`/`title`/`startDate`/
    /// `endDate`/`isEditable` each read off it instead of re-switching over
    /// `self`.
    private struct Fields {
        let idSuffix: String
        let title: String
        let startDate: Date
        let endDate: Date
        let isEditable: Bool
    }

    private var fields: Fields {
        switch self {
        case .commitment(let commitment):
            return Fields(
                idSuffix: "commitment-\(commitment.id)",
                title: commitment.title,
                startDate: commitment.startDate,
                endDate: commitment.endDate,
                isEditable: true
            )
        case .mirroredEvent(let event):
            return Fields(
                idSuffix: "mirrored-\(event.id)",
                title: event.title,
                startDate: event.startDate,
                endDate: event.endDate,
                isEditable: false
            )
        }
    }

    /// Prefixed per case (via `fields.idSuffix`) so a Commitment and a
    /// mirrored event that (implausibly) share a raw UUID never collide as
    /// the same row.
    public var id: String { fields.idSuffix }
    public var title: String { fields.title }
    public var startDate: Date { fields.startDate }
    public var endDate: Date { fields.endDate }

    /// Whether this row can be edited through the Command Center — true
    /// for an owner-created Personal Commitment, false for a mirrored
    /// external Calendar event (spec #1, user story 22).
    public var isEditable: Bool { fields.isEditable }
}
