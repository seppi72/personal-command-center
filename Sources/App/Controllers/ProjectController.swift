import Fluent
import Vapor

struct ProjectResponse: Content {
    let id: UUID
    let name: String
    let dueDate: Date?
    let clientID: UUID?

    init(_ project: Project) throws {
        self.id = try project.requireID()
        self.name = project.name
        self.dueDate = project.dueDate
        self.clientID = project.$client.id
    }
}

struct SaveProjectRequest: Content {
    let name: String
}

/// `dueDate: nil` (or the key omitted entirely) clears the Project's
/// Deadline — same "missing means null" shape as `SetTaskDeadlineRequest`.
struct SetProjectDeadlineRequest: Content {
    let dueDate: Date?
}

/// `clientID: nil` (or the key omitted entirely — Codable's synthesized
/// decoding treats a missing optional key the same as an explicit `null`)
/// both mean "make this Project Client-less", mirroring
/// `AssignTaskProjectRequest`.
struct SetProjectClientRequest: Content {
    let clientID: UUID?
}

struct ProjectController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let projects = routes.grouped("projects")
        projects.get(use: index)
        projects.post(use: create)
        projects.group(":projectID") { project in
            project.put(use: update)
            project.delete(use: delete)
            project.put("deadline", use: setDeadline)
            project.put("client", use: setClient)
        }
    }

    /// Lists every Project, or Projects scoped to one Client when
    /// `?clientID=` is given — same shape as `TaskController.index`'s
    /// optional `?projectID=` filter.
    func index(req: Request) async throws -> [ProjectResponse] {
        var query = Project.query(on: req.db)
        if let clientID = req.query[UUID.self, at: "clientID"] {
            query = query.filter(\.$client.$id == clientID)
        }
        return try await query.all().map(ProjectResponse.init)
    }

    func create(req: Request) async throws -> ProjectResponse {
        let payload = try req.content.decode(SaveProjectRequest.self)
        let project = Project(name: try Self.validatedName(payload.name))
        try await project.save(on: req.db)
        return try ProjectResponse(project)
    }

    func update(req: Request) async throws -> ProjectResponse {
        guard let project = try await findProject(req: req) else {
            throw Abort(.notFound)
        }
        let payload = try req.content.decode(SaveProjectRequest.self)
        project.name = try Self.validatedName(payload.name)
        try await project.save(on: req.db)
        return try ProjectResponse(project)
    }

    /// A Project is created/edited "with a name" — reject an empty or
    /// whitespace-only one rather than persisting a nameless Project.
    private static func validatedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw Abort(.badRequest, reason: "name must not be empty")
        }
        return trimmed
    }

    func delete(req: Request) async throws -> HTTPStatus {
        guard let project = try await findProject(req: req) else {
            throw Abort(.notFound)
        }
        try await Self.verifyNoReferencingTimeEntries(projectID: try project.requireID(), req: req)
        try await project.delete(on: req.db)
        return .noContent
    }

    /// Ticket #29: a Project can't be deleted while any Time Entry still
    /// references it — mirrors `TaskController`'s identical check.
    private static func verifyNoReferencingTimeEntries(projectID: UUID, req: Request) async throws {
        guard try await TimeEntry.query(on: req.db).filter(\.$project.$id == projectID).first() == nil else {
            throw Abort(.badRequest, reason: "cannot delete a Project with Time Entries attached")
        }
    }

    /// Attach, change, or remove (`dueDate: null`) a Project's Deadline —
    /// all three ACs are the same write, mirroring `TaskController.setDeadline`.
    func setDeadline(req: Request) async throws -> ProjectResponse {
        guard let project = try await findProject(req: req) else {
            throw Abort(.notFound)
        }
        let payload = try req.content.decode(SetProjectDeadlineRequest.self)
        project.dueDate = payload.dueDate
        try await project.save(on: req.db)
        return try ProjectResponse(project)
    }

    /// Assign, move, or remove (`clientID: null`) a Project's Client — all
    /// three ACs are the same write (set-or-clear the foreign key), mirroring
    /// `TaskController.assignProject`.
    func setClient(req: Request) async throws -> ProjectResponse {
        guard let project = try await findProject(req: req) else {
            throw Abort(.notFound)
        }
        let payload = try req.content.decode(SetProjectClientRequest.self)
        if let clientID = payload.clientID {
            guard try await PCCClient.find(clientID, on: req.db) != nil else {
                throw Abort(.badRequest, reason: "no such Client")
            }
        }
        project.$client.id = payload.clientID
        try await project.save(on: req.db)
        return try ProjectResponse(project)
    }

    private func findProject(req: Request) async throws -> Project? {
        guard let id = req.parameters.get("projectID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        return try await Project.find(id, on: req.db)
    }
}
