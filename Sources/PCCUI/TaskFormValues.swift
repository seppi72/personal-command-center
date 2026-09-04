import Foundation

/// The fields a Task create/edit form produces together — title, optional
/// notes, the Project *or* Course to (re)assign (never both — ADR-0003;
/// `TaskFormSheet` enforces the exclusivity in its own picker state), and
/// the Deadline to attach/change/clear — bundled so `TasksViewModel` and
/// `TaskFormSheet` pass one value instead of loose parameters that always
/// travel as a set, plus the Kind label to set/clear (ticket #88) and the
/// Sprint to group into within that Project (issue #89).
public struct TaskFormValues: Equatable, Sendable {
    public var title: String
    public var notes: String?
    public var projectID: UUID?
    public var courseID: UUID?
    /// The Sprint to group this Task into — orthogonal to `projectID`
    /// rather than exclusive with it, since a Sprint lives *within* a
    /// Project; only ever a Sprint of `projectID`'s own Project.
    public var sprintID: UUID?
    public var dueDate: Date?
    public var kind: String?

    public init(
        title: String,
        notes: String? = nil,
        projectID: UUID? = nil,
        courseID: UUID? = nil,
        sprintID: UUID? = nil,
        dueDate: Date? = nil,
        kind: String? = nil
    ) {
        self.sprintID = sprintID
        self.title = title
        self.notes = notes
        self.projectID = projectID
        self.courseID = courseID
        self.dueDate = dueDate
        self.kind = kind
    }
}
