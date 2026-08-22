import Foundation

/// Talks to the backend's `/v1/deadlines` endpoint (see
/// `Sources/App/Controllers/DeadlineController.swift`) — the ticket #5
/// sorted view of every Task and Project together. A protocol so the view
/// model can be exercised against a fake in previews/manual testing without
/// a running backend.
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
public struct URLSessionDeadlinesAPIClient: DeadlinesAPIClient {
    private let baseURL: URL
    private let bearerToken: String
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(baseURL: URL, bearerToken: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.bearerToken = bearerToken
        self.session = session
        self.decoder = JSONDecoder()
        // Matches the backend's `ContentConfiguration` (Vapor's default),
        // which encodes/decodes `Date` as an ISO 8601 string rather than
        // `JSONDecoder`'s own default of seconds-since-1970.
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func listDeadlines() async throws -> [DeadlineItem] {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/deadlines"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DeadlinesAPIClientError.unexpectedResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw DeadlinesAPIClientError.serverError(status: http.statusCode)
        }
        return try decoder.decode([DeadlineItem].self, from: data)
    }
}
