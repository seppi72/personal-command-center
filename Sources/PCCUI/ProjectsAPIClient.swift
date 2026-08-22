import Foundation

/// Talks to the backend's `/v1/projects` REST endpoints (see
/// `Sources/App/Controllers/ProjectController.swift`). A protocol so the
/// view model can be exercised against a fake in previews/manual testing
/// without a running backend.
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
public struct URLSessionProjectsAPIClient: ProjectsAPIClient {
    private let baseURL: URL
    private let bearerToken: String
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(baseURL: URL, bearerToken: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.bearerToken = bearerToken
        self.session = session
        self.decoder = JSONDecoder()
        // Matches the backend's `ContentConfiguration` (Vapor's default),
        // which encodes/decodes `Date` as an ISO 8601 string rather than
        // `JSONDecoder`'s own default of seconds-since-1970.
        self.decoder.dateDecodingStrategy = .iso8601
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
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
        let (_, response) = try await session.data(for: request)
        try Self.checkStatus(response)
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

    private func attach<Body: Encodable>(_ body: Body, to request: inout URLRequest) throws {
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        try Self.checkStatus(response)
        return try decoder.decode(Response.self, from: data)
    }

    private func makeRequest(path: String, method: String) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func checkStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ProjectsAPIClientError.unexpectedResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw ProjectsAPIClientError.serverError(status: http.statusCode)
        }
    }
}
