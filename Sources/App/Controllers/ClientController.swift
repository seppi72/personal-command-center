import Fluent
import Vapor

/// Named `PCCClientResponse`, not `ClientResponse`: Vapor itself already
/// declares a `ClientResponse` (the response type of `app.client`/
/// `req.client`'s HTTP client), and an unqualified `ClientResponse` here
/// is ambiguous between the two even though only one is ever in scope for
/// JSON — same reasoning as the `PCCClient` model itself.
struct PCCClientResponse: Content {
    let id: UUID
    let name: String

    init(_ client: PCCClient) throws {
        self.id = try client.requireID()
        self.name = client.name
    }
}

struct SaveClientRequest: Content {
    let name: String
}

struct ClientController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let clients = routes.grouped("clients")
        clients.get(use: index)
        clients.post(use: create)
        clients.group(":clientID") { client in
            client.put(use: update)
            client.delete(use: delete)
        }
    }

    /// Lists every Client — same "no per-client local store" reasoning as
    /// `ProjectController.index` (ADR-0001).
    func index(req: Request) async throws -> [PCCClientResponse] {
        try await PCCClient.query(on: req.db).all().map(PCCClientResponse.init)
    }

    func create(req: Request) async throws -> PCCClientResponse {
        let payload = try req.content.decode(SaveClientRequest.self)
        let client = PCCClient(name: try Self.validatedName(payload.name))
        try await client.save(on: req.db)
        return try PCCClientResponse(client)
    }

    func update(req: Request) async throws -> PCCClientResponse {
        guard let client = try await findClient(req: req) else {
            throw Abort(.notFound)
        }
        let payload = try req.content.decode(SaveClientRequest.self)
        client.name = try Self.validatedName(payload.name)
        try await client.save(on: req.db)
        return try PCCClientResponse(client)
    }

    /// A Client is created/edited "with a name" — reject an empty or
    /// whitespace-only one, mirroring `ProjectController`'s name check.
    private static func validatedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw Abort(.badRequest, reason: "name must not be empty")
        }
        return trimmed
    }

    /// Deleting a Client doesn't delete its Projects — `AddClientToProject`'s
    /// `.setNull` foreign key makes them Client-less instead, the same
    /// orphaning shape `CreatePCCTask`'s `project_id` already has for a
    /// deleted Project.
    func delete(req: Request) async throws -> HTTPStatus {
        guard let client = try await findClient(req: req) else {
            throw Abort(.notFound)
        }
        try await client.delete(on: req.db)
        return .noContent
    }

    private func findClient(req: Request) async throws -> PCCClient? {
        guard let id = req.parameters.get("clientID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        return try await PCCClient.find(id, on: req.db)
    }
}
