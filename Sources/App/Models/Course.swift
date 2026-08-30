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
/// Term (the month and year a Course belongs to, e.g. "September 2026") is
/// modeled as two required integers, `termMonth`/`termYear`, rather than a
/// `Date` — there's no real day-of-month in a Term, and fabricating one (e.g.
/// the 1st) would misrepresent the domain.
///
/// Collides with nothing in Vapor/the stdlib, unlike `PCCClient`/`PCCTask` —
/// named plainly `Course`.
final class Course: Model, @unchecked Sendable {
    static let schema = "courses"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    @Field(key: "term_month")
    var termMonth: Int

    @Field(key: "term_year")
    var termYear: Int

    @OptionalField(key: "due_date")
    var dueDate: Date?

    init() {}

    init(id: UUID? = nil, name: String, termMonth: Int, termYear: Int, dueDate: Date? = nil) {
        self.id = id
        self.name = name
        self.termMonth = termMonth
        self.termYear = termYear
        self.dueDate = dueDate
    }
}
