import Foundation

/// Client-side mirror of the backend's `ProjectResponse` — a container of
/// related Tasks with its own lifecycle (`CONTEXT.md`), optionally carrying
/// a Deadline. Client references land in a later ticket.
public struct Project: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var dueDate: Date?

    public init(id: UUID, name: String, dueDate: Date? = nil) {
        self.id = id
        self.name = name
        self.dueDate = dueDate
    }
}
