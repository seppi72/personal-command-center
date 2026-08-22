import Foundation

/// The fields a Task create/edit form produces together — title, optional
/// notes, and the Project to (re)assign — bundled so `TasksViewModel` and
/// `TaskFormSheet` pass one value instead of three loose parameters that
/// always travel as a set.
public struct TaskFormValues: Equatable, Sendable {
    public var title: String
    public var notes: String?
    public var projectID: UUID?

    public init(title: String, notes: String? = nil, projectID: UUID? = nil) {
        self.title = title
        self.notes = notes
        self.projectID = projectID
    }
}
