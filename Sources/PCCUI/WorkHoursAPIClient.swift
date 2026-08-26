import Foundation

/// Talks to the backend's `GET /v1/work-hours` endpoint (see
/// `Sources/App/Controllers/WorkHoursController.swift`). A protocol so the
/// view model can be exercised against a fake in previews/manual testing
/// without a running backend.
public protocol WorkHoursAPIClient: Sendable {
    /// The Work Hours rollup for `[start, end)`, grouped by `groupBy`.
    func fetchWorkHours(groupBy: WorkHoursGroupBy, start: Date, end: Date) async throws -> [WorkHoursRow]
}

public enum WorkHoursAPIClientError: Error {
    case unexpectedResponse
    case serverError(status: Int)
}

/// The real client: same bearer-token auth as every other route
/// (`BearerTokenAuthMiddleware`) — one token per device, issued out of band.
public struct URLSessionWorkHoursAPIClient: WorkHoursAPIClient {
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
        // which encodes/decodes a JSON body's `Date` as an ISO 8601 string
        // rather than `JSONDecoder`'s own default of seconds-since-1970.
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func fetchWorkHours(groupBy: WorkHoursGroupBy, start: Date, end: Date) async throws -> [WorkHoursRow] {
        // `appendingPathComponent` (used elsewhere in this package's
        // clients for a plain path) percent-escapes "?", so a query string
        // needs `URLComponents` instead — same reasoning as
        // `TasksAPIClient.listTasks`. `start`/`end` are formatted as plain
        // ISO 8601 strings, not left to `URLQueryItem`'s own `Date`
        // handling: `WorkHoursController.validatedRange` parses them by
        // hand with `ISO8601DateFormatter` for the same reason this
        // client's own query-string dates need to, not Vapor's query
        // decoder default of seconds-since-1970.
        var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/work-hours"),
            resolvingAgainstBaseURL: false
        )
        let formatter = ISO8601DateFormatter()
        components?.queryItems = [
            URLQueryItem(name: "groupBy", value: groupBy.rawValue),
            URLQueryItem(name: "start", value: formatter.string(from: start)),
            URLQueryItem(name: "end", value: formatter.string(from: end)),
        ]
        guard let url = components?.url else {
            throw WorkHoursAPIClientError.unexpectedResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try HTTPResponseValidation.checkStatus(
            response,
            unexpectedResponse: WorkHoursAPIClientError.unexpectedResponse,
            serverError: WorkHoursAPIClientError.serverError
        )
        return try decoder.decode([WorkHoursRow].self, from: data)
    }
}
