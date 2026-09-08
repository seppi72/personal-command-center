import Foundation

/// Client-side mirror of the backend's `Semester` — which of the school's
/// three semesters a Term is (`CONTEXT.md`). Closed and not
/// owner-configurable; declaration order is the order semesters run inside a
/// school year, which is the order the Term picker lists them in.
public enum Semester: String, Codable, CaseIterable, Identifiable, Sendable {
    case first, second, summer

    public var id: String { rawValue }

    /// Where this semester falls inside its year — the second half of a
    /// Term's sort key.
    public var sortIndex: Int {
        switch self {
        case .first: return 0
        case .second: return 1
        case .summer: return 2
        }
    }

    /// The semester half of a Term's name — "1st Semester 2026".
    public var displayName: String {
        switch self {
        case .first: return "1st Semester"
        case .second: return "2nd Semester"
        case .summer: return "Summer"
        }
    }

    /// A lecture-hall room-plate-style short code for `TermBadge` — "1S",
    /// "2S", "SU" — standing in for the full Term name shown beside it.
    public var code: String {
        switch self {
        case .first: return "1S"
        case .second: return "2S"
        case .summer: return "SU"
        }
    }
}

/// Client-side mirror of the backend's `TermResponse` — one academic term
/// (`CONTEXT.md`), an entity rather than the month-and-year label a Course
/// used to carry (`docs/adr/0012-term-is-an-entity.md`).
///
/// `displayName` comes from the backend, which derives it from `year` and
/// `semester` — not composed here, so the two can't spell the same Term two
/// ways.
///
/// `startDate`/`endDate` are optional and always travel together: a Term
/// whose span the owner hasn't filled in from the school's academic calendar
/// yet has neither, and is never auto-selected as the current Term
/// (`SchoolBoard.currentTerm(in:reference:)`).
public struct Term: Codable, Identifiable, Equatable, Comparable, Sendable {
    public let id: UUID
    public var year: Int
    public var semester: Semester
    public var displayName: String
    public var startDate: Date?
    public var endDate: Date?

    public init(
        id: UUID, year: Int, semester: Semester, displayName: String, startDate: Date? = nil,
        endDate: Date? = nil
    ) {
        self.id = id
        self.year = year
        self.semester = semester
        self.displayName = displayName
        self.startDate = startDate
        self.endDate = endDate
    }

    /// Whether `date` falls inside this Term's published span. Always
    /// `false` for a Term with no dates set — "not set yet" is not a claim
    /// about today.
    ///
    /// Both ends are inclusive, matching how an academic calendar reads
    /// ("August 11 to December 20") and matching the backend's own overlap
    /// check (`TermController.verifyNoOverlap`).
    public func contains(_ date: Date) -> Bool {
        guard let startDate, let endDate else { return false }
        return date >= startDate && date <= endDate
    }

    /// Year first, then the order semesters run inside a year — not the raw
    /// values, which only sort right by coincidence.
    public static func < (lhs: Term, rhs: Term) -> Bool {
        (lhs.year, lhs.semester.sortIndex) < (rhs.year, rhs.semester.sortIndex)
    }
}
