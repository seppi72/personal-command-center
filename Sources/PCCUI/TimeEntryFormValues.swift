import Foundation

/// The fields a Time Entry create/edit form produces together — a start/end
/// time, optional notes, and the Task/Project/Client/Course to attach to
/// (exactly one, non-optional at the domain level — ADR-0004, though the
/// form can transiently hold none selected before the owner picks one;
/// `TimeEntryFormSheet` disables Save until exactly one is set) — bundled so
/// `WorkViewModel` and `TimeEntryFormSheet` pass one value instead of
/// six loose parameters that always travel as a set (mirrors
/// `TaskFormValues`).
public struct TimeEntryFormValues: Equatable, Sendable {
    public var startDate: Date
    public var endDate: Date
    public var notes: String?
    public var taskID: UUID?
    public var projectID: UUID?
    public var clientID: UUID?
    public var courseID: UUID?

    public init(
        startDate: Date,
        endDate: Date,
        notes: String? = nil,
        taskID: UUID? = nil,
        projectID: UUID? = nil,
        clientID: UUID? = nil,
        courseID: UUID? = nil
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.notes = notes
        self.taskID = taskID
        self.projectID = projectID
        self.clientID = clientID
        self.courseID = courseID
    }

    /// The four id fields read together as one `TimeEntryContainer` — `nil`
    /// unless exactly one is set.
    public var container: TimeEntryContainer? {
        TimeEntryContainer(taskID: taskID, projectID: projectID, clientID: clientID, courseID: courseID)
    }
}
