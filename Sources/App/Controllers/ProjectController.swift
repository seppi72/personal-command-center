import Fluent
import Vapor

struct ProjectResponse: Content {
    let id: UUID
    let name: String

    init(_ project: Project) throws {
        self.id = try project.requireID()
        self.name = project.name
    }
}

struct SaveProjectRequest: Content {
    let name: String
}

struct ProjectController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let projects = routes.grouped("projects")
        projects.get(use: index)
        projects.post(use: create)
        projects.group(":projectID") { project in
            project.put(use: update)
            project.delete(use: delete)
        }
    }

    /// Lists every Project — there is no per-client local store (ADR-0001),
    /// so this is the same list regardless of which device asks.
    func index(req: Request) async throws -> [ProjectResponse] {
        try await Project.query(on: req.db).all().map(ProjectResponse.init)
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
        try await project.delete(on: req.db)
        return .noContent
    }

    private func findProject(req: Request) async throws -> Project? {
        guard let id = req.parameters.get("projectID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        return try await Project.find(id, on: req.db)
    }
}
