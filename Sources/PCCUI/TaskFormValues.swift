import Foundation

/// The fields a Task create/edit form produces together — title, optional
/// notes, the Project to (re)assign, and the Deadline to attach/change/clear
/// — bundled so `TasksViewModel` and `TaskFormSheet` pass one value instead
/// of four loose parameters that always travel as a set.
public struct TaskFormValues: Equatable, Sendable {
    public var title: String
    public var notes: String?
    public var projectID: UUID?
    public var dueDate: Date?

    public init(title: String, notes: String? = nil, projectID: UUID? = nil, dueDate: Date? = nil) {
        self.title = title
        self.notes = notes
        self.projectID = projectID
        self.dueDate = dueDate
    }
}
