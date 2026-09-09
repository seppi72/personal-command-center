import Fluent
import Vapor

/// A container of related Tasks/Deadlines for a single school class, e.g.
/// "CS 301" (`CONTEXT.md`) — analogous to how a Project contains personal
/// Tasks, down to optionally carrying its own Deadline the same way a
/// Project can (`dueDate`). Created directly by the owner each Term, not
/// auto-detected; its Tasks, Deadlines, Time Entries, and (ticket #56)
/// Personal Commitments are entered the same way any other Task, Deadline,
/// Time Entry, or Personal Commitment is — there's no accessible school data
/// source to auto-populate them from, a deliberate decision, not a
/// placeholder for a future sync
/// (`docs/adr/0009-manual-entry-not-lms-integration-for-school.md`).
///
/// A Course belongs to exactly one `Term` — required, never none. Term used
/// to live here as two plain integers, `termMonth`/`termYear`, on the
/// reasoning that a Term was just a month-and-year label with no attributes
/// of its own; it now carries the school's published start and end dates, so
/// it is an entity and this is a reference to it
/// (`docs/adr/0012-term-is-an-entity.md`).
///
/// Collides with nothing in Vapor/the stdlib, unlike `PCCClient`/`PCCTask` —
/// named plainly `Course`.
final class Course: Model, @unchecked Sendable {
    static let schema = "courses"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    @Parent(key: "term_id")
    var term: Term

    @OptionalField(key: "due_date")
    var dueDate: Date?

    /// How much this subject weighs in the General Weighted Average
    /// (`CONTEXT.md`). Required, never optional: a unitless Course would
    /// silently corrupt both GWA and Units Earned, and forcing a nil branch
    /// into every consumer only spreads the problem. Stored as a `Double`
    /// rather than an `Int` so half-unit subjects stay expressible.
    @Field(key: "units")
    var units: Double

    /// The single final mark the school issued for this subject, entered by
    /// the owner (`docs/adr/0013-owner-entered-course-grade-over-computed-gradebook.md`).
    /// `nil` means the subject is ongoing — no mark yet — which is why this
    /// one is optional where `units` is not.
    ///
    /// Stored as its raw `String` rather than through Fluent's `@Enum`, the
    /// same "plain column, translate at the edges" shape
    /// `Account.typeRawValue` and `Term.semesterRawValue` already use.
    @OptionalField(key: "grade")
    var gradeRawValue: String?

    /// The stored raw value as a `Grade`. A row written outside this app
    /// with an unknown mark reads as "no mark yet" rather than trapping —
    /// an ongoing subject is the honest reading of a value this app can't
    /// interpret, and it keeps such a row out of both figures instead of
    /// crashing every request that touches it.
    var grade: Grade? {
        get { gradeRawValue.flatMap(Grade.init(rawValue:)) }
        set { gradeRawValue = newValue?.rawValue }
    }

    init() {}

    init(
        id: UUID? = nil, name: String, termID: Term.IDValue, units: Double,
        grade: Grade? = nil, dueDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.$term.id = termID
        self.units = units
        self.gradeRawValue = grade?.rawValue
        self.dueDate = dueDate
    }
}
