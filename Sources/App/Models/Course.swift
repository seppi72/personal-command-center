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

    init() {}

    init(id: UUID? = nil, name: String, termID: Term.IDValue, dueDate: Date? = nil) {
        self.id = id
        self.name = name
        self.$term.id = termID
        self.dueDate = dueDate
    }
}
