import Fluent
import Vapor

struct SprintResponse: Content {
    let id: UUID
    let name: String
    let startDate: Date
    let endDate: Date
    let projectID: UUID

    init(_ sprint: Sprint) throws {
        self.id = try sprint.requireID()
        self.name = sprint.name
        self.startDate = sprint.startDate
        self.endDate = sprint.endDate
        self.projectID = sprint.$project.id
    }
}

/// A Sprint's Project is set at creation and never reassigned — nothing in
/// the ticket asks for moving a Sprint between Projects, only moving *Tasks*
/// between Sprints (`TaskController.assignSprint`) — so `projectID` only
/// appears here, not in `UpdateSprintRequest`.
struct SaveSprintRequest: Content {
    let projectID: UUID
    let name: String
    let startDate: Date
    let endDate: Date
}

struct UpdateSprintRequest: Content {
    let name: String
    let startDate: Date
    let endDate: Date
}

struct SprintController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let sprints = routes.grouped("sprints")
        sprints.get(use: index)
        sprints.post(use: create)
        sprints.group(":sprintID") { sprint in
            sprint.put(use: update)
            sprint.delete(use: delete)
        }
    }

    /// Lists the Sprints in one Project — `?projectID=` is required, unlike
    /// `ProjectController.index`'s optional `?clientID=`, because a Sprint
    /// has no meaning outside a Project: there's no "list all Sprints
    /// globally" story to support.
    func index(req: Request) async throws -> [SprintResponse] {
        guard let projectID = req.query[UUID.self, at: "projectID"] else {
            throw Abort(.badRequest, reason: "projectID is required")
        }
        return try await Sprint.query(on: req.db)
            .filter(\.$project.$id == projectID)
            .all()
            .map(SprintResponse.init)
    }

    func create(req: Request) async throws -> SprintResponse {
        let payload = try req.content.decode(SaveSprintRequest.self)
        guard try await Project.find(payload.projectID, on: req.db) != nil else {
            throw Abort(.badRequest, reason: "no such Project")
        }
        let sprint = Sprint(
            name: try Self.validatedName(payload.name),
            startDate: payload.startDate,
            endDate: try Self.validatedEndDate(payload.endDate, after: payload.startDate),
            projectID: payload.projectID
        )
        try await sprint.save(on: req.db)
        return try SprintResponse(sprint)
    }

    func update(req: Request) async throws -> SprintResponse {
        guard let sprint = try await findSprint(req: req) else {
            throw Abort(.notFound)
        }
        let payload = try req.content.decode(UpdateSprintRequest.self)
        sprint.name = try Self.validatedName(payload.name)
        sprint.startDate = payload.startDate
        sprint.endDate = try Self.validatedEndDate(payload.endDate, after: payload.startDate)
        try await sprint.save(on: req.db)
        return try SprintResponse(sprint)
    }

    /// Deleting a Sprint doesn't delete its Tasks — `AddSprintToPCCTask`'s
    /// `.setNull` foreign key makes them Sprint-less instead, the same
    /// orphaning shape `ClientController.delete` already has for a deleted
    /// Client's Projects.
    func delete(req: Request) async throws -> HTTPStatus {
        guard let sprint = try await findSprint(req: req) else {
            throw Abort(.notFound)
        }
        try await sprint.delete(on: req.db)
        return .noContent
    }

    /// A Sprint is created/edited "with a name" — reject an empty or
    /// whitespace-only one, mirroring `ProjectController`'s name check.
    private static func validatedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw Abort(.badRequest, reason: "name must not be empty")
        }
        return trimmed
    }

    /// A Sprint is "time-boxed" (`CONTEXT.md`) — reject a range that ends
    /// before it starts rather than persisting a Sprint whose dates don't
    /// make sense.
    private static func validatedEndDate(_ endDate: Date, after startDate: Date) throws -> Date {
        guard endDate >= startDate else {
            throw Abort(.badRequest, reason: "endDate must not be before startDate")
        }
        return endDate
    }

    private func findSprint(req: Request) async throws -> Sprint? {
        guard let id = req.parameters.get("sprintID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        return try await Sprint.find(id, on: req.db)
    }
}
