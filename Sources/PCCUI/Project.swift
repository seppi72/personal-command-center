import Foundation

/// Client-side mirror of the backend's `ProjectResponse` — a container of
/// related Tasks with its own lifecycle (`CONTEXT.md`). This slice only
/// carries a name; Deadline/Client references land in later tickets.
public struct Project: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}
