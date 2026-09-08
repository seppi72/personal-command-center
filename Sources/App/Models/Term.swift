import Fluent
import Vapor

/// Which of the school's three semesters a Term is (`CONTEXT.md`). The
/// owner's school runs on semesters, not quarters or trimesters, so this
/// list is closed and not owner-configurable — the same fixed-mapping shape
/// `AccountType` already has.
///
/// Declaration order is the order semesters run inside a school year, which
/// is what `sortIndex` exposes: 1st Semester, then 2nd Semester, then
/// Summer. `CaseIterable`'s order is relied on for the picker the client
/// renders, so reordering these cases reorders that menu.
///
/// Raw values are camelCase to match this API's existing JSON convention
/// (e.g. `AccountType.creditCard`) rather than the "1st Semester" Title Case
/// `CONTEXT.md` prose uses.
enum Semester: String, Codable, CaseIterable, Sendable {
    case first, second, summer

    /// Where this semester falls inside its year — the second half of a
    /// Term's sort key, since a Term orders by year first and by semester
    /// within a year.
    var sortIndex: Int {
        switch self {
        case .first: return 0
        case .second: return 1
        case .summer: return 2
        }
    }

    /// The semester half of a Term's display name — "1st Semester 2026",
    /// "Summer 2026".
    var displayName: String {
        switch self {
        case .first: return "1st Semester"
        case .second: return "2nd Semester"
        case .summer: return "Summer"
        }
    }
}

/// One academic term at the owner's school (`CONTEXT.md`) — an entity, not
/// the month-and-year label a Course used to carry in `termMonth`/`termYear`
/// (`docs/adr/0012-term-is-an-entity.md`). A Term has attributes of its own:
/// the start and end dates published in the school's academic calendar, and
/// the Courses taken in it.
///
/// Identified by `year` plus `semester`, unique on that pair (`CreateTerm`).
/// A semester never crosses a year boundary at this school, so that pair is
/// unambiguous and no school-year span ("2026-2027") is needed.
///
/// `displayName` is **derived**, never stored or set by a request. Free text
/// would let "1st Sem 2026" and "First Semester 2026" exist as two rows with
/// Courses split between them, quietly breaking every per-Term figure.
///
/// `startDate`/`endDate` are optional because the migration that promoted
/// Term to an entity can't know them (`AddTermToCourse`) — a Term generated
/// from old `termMonth`/`termYear` data has no calendar span to copy, and
/// fabricating one would silently mislabel which Term is current. They are
/// set or cleared together: half a range can neither be checked for overlap
/// against another Term nor asked whether it contains today, so
/// `TermController` rejects one without the other.
///
/// `semester` is stored as its raw `String` rather than through Fluent's
/// `@Enum` (a native Postgres enum type), the same "plain column, translate
/// at the edges" shape `Account.typeRawValue` already uses.
///
/// Collides with nothing in Vapor/Fluent/the stdlib, unlike `PCCClient`/
/// `PCCTask` — named plainly `Term`.
final class Term: Model, @unchecked Sendable {
    static let schema = "terms"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "year")
    var year: Int

    @Field(key: "semester")
    var semesterRawValue: String

    @OptionalField(key: "start_date")
    var startDate: Date?

    @OptionalField(key: "end_date")
    var endDate: Date?

    /// The stored raw value as a `Semester`. Falls back to `.first` for a
    /// row written outside this app rather than trapping — matching
    /// `Account.type`'s own accessor.
    var semester: Semester {
        get { Semester(rawValue: semesterRawValue) ?? .first }
        set { semesterRawValue = newValue.rawValue }
    }

    /// e.g. "1st Semester 2026" — the Term's owner-facing name, derived from
    /// `semester` and `year` on every read so two Terms can never disagree
    /// about how the same year-and-semester is spelled.
    var displayName: String {
        "\(semester.displayName) \(year)"
    }

    init() {}

    init(
        id: UUID? = nil, year: Int, semester: Semester, startDate: Date? = nil,
        endDate: Date? = nil
    ) {
        self.id = id
        self.year = year
        self.semesterRawValue = semester.rawValue
        self.startDate = startDate
        self.endDate = endDate
    }
}
