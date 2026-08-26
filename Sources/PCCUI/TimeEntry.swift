import Foundation

/// Client-side mirror of the backend's `TimeEntryResponse` — a record
/// spanning a start and end time (`CONTEXT.md`), attached to exactly one of
/// Task, Project, Client, or Course
/// (`docs/adr/0004-time-entry-container-includes-course.md`).
public struct TimeEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var startDate: Date
    public var endDate: Date
    public var notes: String?
    public var taskID: UUID?
    public var projectID: UUID?
    public var clientID: UUID?
    public var courseID: UUID?

    public init(
        id: UUID,
        startDate: Date,
        endDate: Date,
        notes: String? = nil,
        taskID: UUID? = nil,
        projectID: UUID? = nil,
        clientID: UUID? = nil,
        courseID: UUID? = nil
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.notes = notes
        self.taskID = taskID
        self.projectID = projectID
        self.clientID = clientID
        self.courseID = courseID
    }
}
