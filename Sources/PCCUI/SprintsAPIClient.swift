import Foundation

/// Talks to the backend's `/v1/sprints` REST endpoints (see
/// `Sources/App/Controllers/SprintController.swift`). A protocol so the view
/// model can be exercised against a fake in previews/manual testing without
/// a running backend.
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
public struct URLSessionSprintsAPIClient: SprintsAPIClient {
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

    public func listSprints(projectID: UUID) async throws -> [Sprint] {
        // `appendingPathComponent` (used by `makeRequest(path:method:)`)
        // percent-escapes "?", so a query string needs `URLComponents`
        // instead (mirrors `URLSessionTasksAPIClient.listTasks`).
        var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/sprints"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "projectID", value: projectID.uuidString)]
        guard let url = components?.url else {
            throw SprintsAPIClientError.unexpectedResponse
        }
        return try await send(makeRequest(url: url, method: "GET"))
    }

    public func createSprint(projectID: UUID, name: String, startDate: Date, endDate: Date) async throws -> Sprint {
        var request = makeRequest(path: "v1/sprints", method: "POST")
        try attach(SaveSprintPayload(projectID: projectID, name: name, startDate: startDate, endDate: endDate), to: &request)
        return try await send(request)
    }

    public func updateSprint(id: UUID, name: String, startDate: Date, endDate: Date) async throws -> Sprint {
        var request = makeRequest(path: "v1/sprints/\(id)", method: "PUT")
        try attach(UpdateSprintPayload(name: name, startDate: startDate, endDate: endDate), to: &request)
        return try await send(request)
    }

    public func deleteSprint(id: UUID) async throws {
        let request = makeRequest(path: "v1/sprints/\(id)", method: "DELETE")
        let (_, response) = try await session.data(for: request)
        try HTTPResponseValidation.checkStatus(
            response,
            unexpectedResponse: SprintsAPIClientError.unexpectedResponse,
            serverError: SprintsAPIClientError.serverError
        )
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

    private func attach<Body: Encodable>(_ body: Body, to request: inout URLRequest) throws {
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        try HTTPResponseValidation.checkStatus(
            response,
            unexpectedResponse: SprintsAPIClientError.unexpectedResponse,
            serverError: SprintsAPIClientError.serverError
        )
        return try decoder.decode(Response.self, from: data)
    }

    private func makeRequest(path: String, method: String) -> URLRequest {
        makeRequest(url: baseURL.appendingPathComponent(path), method: method)
    }

    private func makeRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        return request
    }
}
