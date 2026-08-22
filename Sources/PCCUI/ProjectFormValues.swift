import Foundation

/// The fields a Project create/edit form produces together — name and the
/// Deadline to attach/change/clear — bundled so `ProjectsViewModel` and
/// `ProjectFormSheet` pass one value instead of two loose parameters that
/// always travel as a set (mirrors `TaskFormValues`).
public struct ProjectFormValues: Equatable, Sendable {
    public var name: String
    public var dueDate: Date?

    public init(name: String, dueDate: Date? = nil) {
        self.name = name
        self.dueDate = dueDate
    }
}
