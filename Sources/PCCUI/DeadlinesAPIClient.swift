import Foundation

/// Talks to the backend's `/v1/deadlines` endpoint (see
/// `Sources/App/Controllers/DeadlineController.swift`) — the ticket #5
/// sorted view of every Task and Project together. A protocol so a different
/// implementation could stand in during previews/manual testing without a
/// running backend — no such fake exists in this package yet, but the seam
/// is here for one.
public protocol DeadlinesAPIClient: Sendable {
    /// Tasks and Projects together, already ordered by Deadline proximity
    /// with undated items included (the backend does the sorting).
    func listDeadlines() async throws -> [DeadlineItem]
}

public enum DeadlinesAPIClientError: Error {
    case unexpectedResponse
    case serverError(status: Int)
}

/// The real client: same bearer-token auth as every other route
/// (`BearerTokenAuthMiddleware`) — one token per device, issued out of band.
/// Transport (request construction, encoding/decoding, status validation) is
/// `PCCHTTPTransport`'s; this struct owns only its own endpoints and payload
/// shapes.
public struct URLSessionDeadlinesAPIClient: DeadlinesAPIClient {
    private let transport: PCCHTTPTransport

    public init(baseURL: URL, bearerToken: String, session: URLSession = .shared) {
        self.transport = PCCHTTPTransport(baseURL: baseURL, bearerToken: bearerToken, session: session)
    }

    public func listDeadlines() async throws -> [DeadlineItem] {
        let request = try makeRequest(path: "v1/deadlines", method: "GET")
        return try await send(request)
    }

    private func makeRequest(
        path: String,
        method: String,
        query: [String: PCCHTTPTransport.QueryValue?] = [:]
    ) throws -> URLRequest {
        try transport.makeRequest(path: path, method: method, query: query)
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        try await transport.send(
            request,
            unexpectedResponse: DeadlinesAPIClientError.unexpectedResponse,
            serverError: DeadlinesAPIClientError.serverError
        )
    }
}
