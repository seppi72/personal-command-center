import Foundation

/// `TimeEntry.taskID`/`projectID`/`clientID`/`courseID` (and
/// `TimeEntryFormValues`' mirror of them) read together as one value — a
/// Time Entry attaches to exactly one of these, required, never none, never
/// more than one (ADR-0004; see
/// `Sources/App/Models/TimeEntryContainer.swift` for the backend's
/// counterpart). Bundling them here makes "exactly one of these four" a
/// type `TimeEntriesViewModel`/`TimeEntryFormSheet` reason about once,
/// rather than a rule re-derived at each call site that touches all four
/// fields.
public enum TimeEntryContainer: Equatable, Sendable {
    case task(UUID)
    case project(UUID)
    case client(UUID)
    case course(UUID)

    /// `nil` when zero or more than one of the four ids is given — a Time
    /// Entry's container is required and mutually exclusive, unlike
    /// `TaskContainer`'s optional pair, so there's no single "priority"
    /// value to fall back on here the way `TaskContainer.init` picks one.
    public init?(taskID: UUID?, projectID: UUID?, clientID: UUID?, courseID: UUID?) {
        let given = [taskID, projectID, clientID, courseID].compactMap { $0 }
        guard given.count == 1 else { return nil }
        if let taskID { self = .task(taskID) }
        else if let projectID { self = .project(projectID) }
        else if let clientID { self = .client(clientID) }
        else { self = .course(courseID!) }
    }
}
