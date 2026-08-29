import Foundation

/// Talks to the backend's `/v1/notifications` endpoints (see
/// `Sources/App/Controllers/NotificationController.swift`). A protocol so a
/// different implementation could stand in during previews/manual testing
/// without a running backend — no such fake exists in this package yet, but
/// the seam is here for one. No create/update/delete methods — nothing on
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
/// Transport (request construction, encoding/decoding, status validation) is
/// `PCCHTTPTransport`'s; this struct owns only its own endpoints and payload
/// shapes.
public struct URLSessionNotificationsAPIClient: NotificationsAPIClient {
    private let transport: PCCHTTPTransport

    public init(baseURL: URL, bearerToken: String, session: URLSession = .shared) {
        self.transport = PCCHTTPTransport(baseURL: baseURL, bearerToken: bearerToken, session: session)
    }

    public func listNotifications() async throws -> [NotificationItem] {
        try await send(makeRequest(path: "v1/notifications", method: "GET"))
    }

    public func dismissNotification(id: UUID) async throws -> NotificationItem {
        try await send(makeRequest(path: "v1/notifications/\(id)/dismiss", method: "POST"))
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
            unexpectedResponse: NotificationsAPIClientError.unexpectedResponse,
            serverError: NotificationsAPIClientError.serverError
        )
    }
}
