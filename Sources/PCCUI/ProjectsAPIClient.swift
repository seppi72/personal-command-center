import Foundation

/// Talks to the backend's `/v1/projects` REST endpoints (see
/// `Sources/App/Controllers/ProjectController.swift`). A protocol so a
/// different implementation could stand in during previews/manual testing
/// without a running backend — no such fake exists in this package yet, but
/// the seam is here for one.
public protocol ProjectsAPIClient: Sendable {
    func listProjects() async throws -> [Project]
    func createProject(name: String) async throws -> Project
    func updateProject(id: UUID, name: String) async throws -> Project
    func deleteProject(id: UUID) async throws
    /// Attaches, changes, or removes (`dueDate: nil`) a Project's Deadline.
    func setProjectDeadline(id: UUID, dueDate: Date?) async throws -> Project
}

public enum ProjectsAPIClientError: Error {
    case unexpectedResponse
    case serverError(status: Int)
}

/// The real client: same bearer-token auth as every other route
/// (`BearerTokenAuthMiddleware`) — one token per device, issued out of band.
/// Transport (request construction, encoding/decoding, status validation) is
/// `PCCHTTPTransport`'s; this struct owns only its own endpoints and payload
/// shapes.
public struct URLSessionProjectsAPIClient: ProjectsAPIClient {
    private let transport: PCCHTTPTransport

    public init(baseURL: URL, bearerToken: String, session: URLSession = .shared) {
        self.transport = PCCHTTPTransport(baseURL: baseURL, bearerToken: bearerToken, session: session)
    }

    public func listProjects() async throws -> [Project] {
        let request = try makeRequest(path: "v1/projects", method: "GET")
        return try await send(request)
    }

    public func createProject(name: String) async throws -> Project {
        var request = try makeRequest(path: "v1/projects", method: "POST")
        try attach(SaveProjectPayload(name: name), to: &request)
        return try await send(request)
    }

    public func updateProject(id: UUID, name: String) async throws -> Project {
        var request = try makeRequest(path: "v1/projects/\(id)", method: "PUT")
        try attach(SaveProjectPayload(name: name), to: &request)
        return try await send(request)
    }

    public func deleteProject(id: UUID) async throws {
        let request = try makeRequest(path: "v1/projects/\(id)", method: "DELETE")
        try await sendNoBody(request)
    }

    public func setProjectDeadline(id: UUID, dueDate: Date?) async throws -> Project {
        var request = try makeRequest(path: "v1/projects/\(id)/deadline", method: "PUT")
        try attach(SetProjectDeadlinePayload(dueDate: dueDate), to: &request)
        return try await send(request)
    }

    private struct SaveProjectPayload: Encodable {
        let name: String
    }

    private struct SetProjectDeadlinePayload: Encodable {
        let dueDate: Date?
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
            unexpectedResponse: ProjectsAPIClientError.unexpectedResponse,
            serverError: ProjectsAPIClientError.serverError
        )
    }

    private func sendNoBody(_ request: URLRequest) async throws {
        try await transport.sendExpectingNoBody(
            request,
            unexpectedResponse: ProjectsAPIClientError.unexpectedResponse,
            serverError: ProjectsAPIClientError.serverError
        )
    }
}
