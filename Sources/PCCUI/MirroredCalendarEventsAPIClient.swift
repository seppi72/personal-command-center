import Foundation

/// Talks to the backend's read-only `/v1/calendar-events` endpoint (see
/// `Sources/App/Controllers/MirroredCalendarEventController.swift`). A
/// protocol so the view model can be exercised against a fake in
/// previews/manual testing without a running backend. No
/// create/update/delete methods — the cache isn't owner-editable.
public protocol MirroredCalendarEventsAPIClient: Sendable {
    func listMirroredCalendarEvents() async throws -> [MirroredCalendarEvent]
}

public enum MirroredCalendarEventsAPIClientError: Error {
    case unexpectedResponse
    case serverError(status: Int)
}

/// The real client: same bearer-token auth as every other route
/// (`BearerTokenAuthMiddleware`) — one token per device, issued out of band.
public struct URLSessionMirroredCalendarEventsAPIClient: MirroredCalendarEventsAPIClient {
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

    public func listMirroredCalendarEvents() async throws -> [MirroredCalendarEvent] {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/calendar-events"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MirroredCalendarEventsAPIClientError.unexpectedResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw MirroredCalendarEventsAPIClientError.serverError(status: http.statusCode)
        }
        return try decoder.decode([MirroredCalendarEvent].self, from: data)
    }
}
