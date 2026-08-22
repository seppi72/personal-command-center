import Foundation

/// Client-side mirror of the backend's `TaskResponse` — the atomic unit of
/// work (`CONTEXT.md`), optionally assigned to a Project.
///
/// Named `PCCTask` in Swift only, to avoid shadowing `_Concurrency.Task`
/// throughout this module (`ProjectsView` already relies on bare
/// `Task { ... }`). The domain term "Task" is what shows up in the API and
/// UI text — see `Sources/App/Models/PCCTask.swift` for the same tradeoff
/// on the backend.
public struct PCCTask: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var notes: String?
    public var isComplete: Bool
    public var projectID: UUID?

    public init(id: UUID, title: String, notes: String? = nil, isComplete: Bool = false, projectID: UUID? = nil) {
        self.id = id
        self.title = title
        self.notes = notes
        self.isComplete = isComplete
        self.projectID = projectID
    }
}
