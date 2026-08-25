import Foundation

/// Client-side mirror of the backend's `DeadlineItemResponse` — one Task,
/// Project, or Course flattened to just what the sorted Deadline view needs.
/// `isComplete` is `nil` for a Project/Course — there's no such concept at
/// that level — rather than forcing a `false` that would read as "not done".
public struct DeadlineItem: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case task
        case project
        case course
    }

    public let kind: Kind
    public let id: UUID
    public let title: String
    public let dueDate: Date?
    public let isComplete: Bool?

    public init(kind: Kind, id: UUID, title: String, dueDate: Date? = nil, isComplete: Bool? = nil) {
        self.kind = kind
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.isComplete = isComplete
    }
}
