import Fluent
import Vapor

/// A container of related Tasks/Deadlines for a single school class, e.g.
/// "CS 301" (`CONTEXT.md`) — analogous to how a Project contains personal
/// Tasks, down to optionally carrying its own Deadline the same way a
/// Project can (`dueDate`). Created directly by the owner each Term, not
/// auto-detected; the Tasks/Deadlines inside it are what auto-populate later,
/// from a school data source (ticket #20, out of scope here).
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
