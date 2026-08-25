import Foundation

/// Client-side mirror of the backend's `SprintResponse` — a time-boxed
/// iteration within one Project that Tasks can be grouped into
/// (`CONTEXT.md`). A Sprint is scoped to the Project it was created in for
/// its lifetime, so `projectID` is never reassigned client-side either.
public struct Sprint: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var startDate: Date
    public var endDate: Date
    public let projectID: UUID

    public init(id: UUID, name: String, startDate: Date, endDate: Date, projectID: UUID) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.projectID = projectID
    }
}
