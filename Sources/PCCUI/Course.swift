import Foundation

/// Client-side mirror of the backend's `CourseResponse` — a container of
/// related Tasks/Deadlines for a single school class (`CONTEXT.md`),
/// analogous to `Project` down to optionally carrying its own Deadline.
///
/// Carries its whole `Term`, not just `termID`: every place this screen
/// shows a Course it also labels, badges or groups it by Term, and the
/// backend nests the Term in its response so no second fetch or client-side
/// join is needed (`docs/adr/0012-term-is-an-entity.md`).
///
/// Collides with nothing in Swift/Foundation, unlike `PCCClient`/`PCCTask` —
/// named plainly `Course`.
public struct Course: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var termID: UUID
    public var term: Term
    public var dueDate: Date?
    /// How much this subject weighs in the General Weighted Average — always
    /// present, never optional (issue #92).
    public var units: Double
    /// The final mark, or `nil` while the subject is ongoing.
    public var grade: Grade?

    public init(
        id: UUID, name: String, term: Term, units: Double, grade: Grade? = nil,
        dueDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.termID = term.id
        self.term = term
        self.units = units
        self.grade = grade
        self.dueDate = dueDate
    }
}
