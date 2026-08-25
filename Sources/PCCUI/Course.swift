import Foundation

/// Client-side mirror of the backend's `CourseResponse` — a container of
/// related Tasks/Deadlines for a single school class (`CONTEXT.md`),
/// analogous to `Project` down to optionally carrying its own Deadline.
///
/// Term (the month and year a Course belongs to) is modeled as two required
/// integers, `termMonth`/`termYear`, rather than a `Date` — matching the
/// backend model, see `Sources/App/Models/Course.swift`'s doc comment.
///
/// Collides with nothing in Swift/Foundation, unlike `PCCClient`/`PCCTask` —
/// named plainly `Course`.
public struct Course: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var termMonth: Int
    public var termYear: Int
    public var dueDate: Date?

    public init(id: UUID, name: String, termMonth: Int, termYear: Int, dueDate: Date? = nil) {
        self.id = id
        self.name = name
        self.termMonth = termMonth
        self.termYear = termYear
        self.dueDate = dueDate
    }
}
