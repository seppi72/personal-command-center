import Foundation

/// Talks to the backend's `/v1/sprints` REST endpoints (see
/// `Sources/App/Controllers/SprintController.swift`). A protocol so a
/// different implementation could stand in during previews/manual testing
/// without a running backend — no such fake exists in this package yet, but
/// the seam is here for one.
public protocol SprintsAPIClient: Sendable {
    /// A Sprint has no meaning outside a Project, so listing is always
    /// scoped to one — there's no "list all Sprints" call, unlike
    /// `ClientsAPIClient.listClients()`.
    func listSprints(projectID: UUID) async throws -> [Sprint]
    func createSprint(projectID: UUID, name: String, startDate: Date, endDate: Date) async throws -> Sprint
    func updateSprint(id: UUID, name: String, startDate: Date, endDate: Date) async throws -> Sprint
    func deleteSprint(id: UUID) async throws
}

public enum SprintsAPIClientError: Error {
    case unexpectedResponse
    case serverError(status: Int)
}

/// The real client: same bearer-token auth as every other route
/// (`BearerTokenAuthMiddleware`) — one token per device, issued out of band.
/// Transport (request construction, encoding/decoding, status validation) is
/// `PCCHTTPTransport`'s; this struct owns only its own endpoints and payload
/// shapes.
public struct URLSessionSprintsAPIClient: SprintsAPIClient {
    private let transport: PCCHTTPTransport

    public init(baseURL: URL, bearerToken: String, session: URLSession = .shared) {
        self.transport = PCCHTTPTransport(baseURL: baseURL, bearerToken: bearerToken, session: session)
    }

    public func listSprints(projectID: UUID) async throws -> [Sprint] {
        let request = try makeRequest(
            path: "v1/sprints",
            method: "GET",
            query: ["projectID": .uuid(projectID)]
        )
        return try await send(request)
    }

    public func createSprint(projectID: UUID, name: String, startDate: Date, endDate: Date) async throws -> Sprint {
        var request = try makeRequest(path: "v1/sprints", method: "POST")
        try attach(SaveSprintPayload(projectID: projectID, name: name, startDate: startDate, endDate: endDate), to: &request)
        return try await send(request)
    }

    public func updateSprint(id: UUID, name: String, startDate: Date, endDate: Date) async throws -> Sprint {
        var request = try makeRequest(path: "v1/sprints/\(id)", method: "PUT")
        try attach(UpdateSprintPayload(name: name, startDate: startDate, endDate: endDate), to: &request)
        return try await send(request)
    }

    public func deleteSprint(id: UUID) async throws {
        let request = try makeRequest(path: "v1/sprints/\(id)", method: "DELETE")
        try await sendNoBody(request)
    }

    private struct SaveSprintPayload: Encodable {
        let projectID: UUID
        let name: String
        let startDate: Date
        let endDate: Date
    }

    private struct UpdateSprintPayload: Encodable {
        let name: String
        let startDate: Date
        let endDate: Date
    }

    private func makeRequest(
        path: String,
        method: String,
        query: [String: PCCHTTPTransport.QueryValue?] = [:]
    ) throws -> URLRequest {
        try transport.makeRequest(path: path, method: method, query: query)
    }

    private func attach<Body: Encodable>(_ body: Body, to request: inout URLRequest) throws {
        try transport.attach(body, to: &request)
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        try await transport.send(
            request,
            unexpectedResponse: SprintsAPIClientError.unexpectedResponse,
            serverError: SprintsAPIClientError.serverError
        )
    }

    private func sendNoBody(_ request: URLRequest) async throws {
        try await transport.sendExpectingNoBody(
            request,
            unexpectedResponse: SprintsAPIClientError.unexpectedResponse,
            serverError: SprintsAPIClientError.serverError
        )
    }
}
