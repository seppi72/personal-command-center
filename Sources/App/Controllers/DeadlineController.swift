import Fluent
import Vapor

/// One Task or Project, flattened to just what the sorted Deadline view
/// needs. `isComplete` is `nil` for a Project — there's no such concept at
/// that level — rather than forcing a `false` that would read as "not done".
struct DeadlineItemResponse: Content {
    enum Kind: String, Codable, Equatable {
        case task
        case project
    }

    let kind: Kind
    let id: UUID
    let title: String
    let dueDate: Date?
    let isComplete: Bool?

    init(_ task: PCCTask) throws {
        self.kind = .task
        self.id = try task.requireID()
        self.title = task.title
        self.dueDate = task.dueDate
        self.isComplete = task.isComplete
    }

    init(_ project: Project) throws {
        self.kind = .project
        self.id = try project.requireID()
        self.title = project.name
        self.dueDate = project.dueDate
        self.isComplete = nil
    }
}

/// The ticket #5 "sorted view": every Task and Project together, ordered by
/// Deadline proximity, with undated items still present rather than filtered
/// out.
struct DeadlineController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get("deadlines", use: index)
    }

    /// Fluent has no cross-model UNION here, so both tables are fetched and
    /// merged in memory — a fine tradeoff at this system's single-user scale
    /// (`CONTEXT.md`).
    func index(req: Request) async throws -> [DeadlineItemResponse] {
        async let taskModels = PCCTask.query(on: req.db).all()
        async let projectModels = Project.query(on: req.db).all()
        let items = try await taskModels.map(DeadlineItemResponse.init)
            + (try await projectModels.map(DeadlineItemResponse.init))
        return items.sorted(by: Self.areInProximityOrder)
    }

    /// The `sorted(by:)` predicate for Deadline proximity: dated items sort
    /// ascending by due date (soonest first); an undated item never outranks
    /// a dated one, so all undated items land after every dated one. Within
    /// a tie (same due date, or both undated) items sort by title so the
    /// ordering is deterministic rather than incidental to query order.
    /// Named to match the stdlib's own two-argument comparator convention
    /// (cf. `sorted(by: areInIncreasingOrder)`), not as a single-item
    /// predicate.
    static func areInProximityOrder(_ lhs: DeadlineItemResponse, _ rhs: DeadlineItemResponse) -> Bool {
        switch (lhs.dueDate, rhs.dueDate) {
        case let (left?, right?) where left != right:
            return left < right
        case (nil, .some):
            return false
        case (.some, nil):
            return true
        default:
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }
}
