import Foundation

/// Talks to the backend's `/v1/notifications` endpoints (see
/// `Sources/App/Controllers/NotificationController.swift`). A protocol so
/// the view model can be exercised against a fake in previews/manual testing
/// without a running backend. No create/update/delete methods — nothing on
/// this screen creates a Notification; only `dismiss` is owner-editable.
public protocol NotificationsAPIClient: Sendable {
    func listNotifications() async throws -> [NotificationItem]
    func dismissNotification(id: UUID) async throws -> NotificationItem
}

public enum NotificationsAPIClientError: Error {
    case unexpectedResponse
    case serverError(status: Int)
}

/// The real client: same bearer-token auth as every other route
/// (`BearerTokenAuthMiddleware`) — one token per device, issued out of band.
public struct URLSessionNotificationsAPIClient: NotificationsAPIClient {
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

    public func listNotifications() async throws -> [NotificationItem] {
        try await send(makeRequest(path: "v1/notifications", method: "GET"))
    }

    public func dismissNotification(id: UUID) async throws -> NotificationItem {
        try await send(makeRequest(path: "v1/notifications/\(id)/dismiss", method: "POST"))
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        try HTTPResponseValidation.checkStatus(
            response,
            unexpectedResponse: NotificationsAPIClientError.unexpectedResponse,
            serverError: NotificationsAPIClientError.serverError
        )
        return try decoder.decode(Response.self, from: data)
    }

    private func makeRequest(path: String, method: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        return request
    }
}
