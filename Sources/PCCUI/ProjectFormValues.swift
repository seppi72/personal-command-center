import Foundation

/// The fields a Project create/edit form produces together — name, the
/// Deadline to attach/change/clear, and the Course to assign/clear (ticket
/// #88) — bundled so `WorkViewModel` and `ProjectFormSheet` pass one
/// value instead of loose parameters that always travel as a set (mirrors
/// `TaskFormValues`).
///
/// No `clientID` counterpart yet: a Project's Client isn't editable from
/// this form (`ProjectsAPIClient` has no client-assignment call), so nothing
/// here has to reconcile ADR-0011's Client-xor-Course choice — assigning a
/// Course clears any Client server-side (`ProjectController.setCourse`).
public struct ProjectFormValues: Equatable, Sendable {
    public var name: String
    public var dueDate: Date?
    public var courseID: UUID?

    public init(name: String, dueDate: Date? = nil, courseID: UUID? = nil) {
        self.name = name
        self.dueDate = dueDate
        self.courseID = courseID
    }
}
