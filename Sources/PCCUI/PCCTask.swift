import Foundation

/// Client-side mirror of the backend's `TaskResponse` — the atomic unit of
/// work (`CONTEXT.md`), optionally assigned to a Project or a Course (never
/// both — ADR-0003).
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
    public var dueDate: Date?
    public var courseID: UUID?
    /// When this Task was last marked complete — `nil` while incomplete.
    /// Backs the Overview dashboard's on-time completion rate (whether this
    /// is on/before `dueDate`); only accurate for Tasks completed after this
    /// field was introduced, since nothing backfills it retroactively.
    public var completedAt: Date?

    public init(
        id: UUID,
        title: String,
        notes: String? = nil,
        isComplete: Bool = false,
        projectID: UUID? = nil,
        dueDate: Date? = nil,
        courseID: UUID? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.isComplete = isComplete
        self.projectID = projectID
        self.dueDate = dueDate
        self.courseID = courseID
        self.completedAt = completedAt
    }
}
