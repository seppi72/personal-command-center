import Foundation

/// `PCCTask.projectID`/`courseID` (and `TaskFormValues`' mirror of them) read
/// together as one value instead of a loose pair — a Task belongs to at most
/// one of {Project, Course}, never both (ADR-0003; see
/// `Sources/App/Models/TaskContainer.swift` for the backend's counterpart).
/// Bundling them here makes "at most one of these two" a type
/// `WorkViewModel` reasons about once, rather than a rule re-derived at
/// each call site that touches both fields.
enum TaskContainer: Equatable {
    case project(UUID)
    case course(UUID)
    case none

    /// `courseID` takes priority when both are somehow set — the form itself
    /// keeps them mutually exclusive, but this is the one place that has to
    /// pick if it's ever wrong.
    init(projectID: UUID?, courseID: UUID?) {
        if let courseID {
            self = .course(courseID)
        } else if let projectID {
            self = .project(projectID)
        } else {
            self = .none
        }
    }
}
