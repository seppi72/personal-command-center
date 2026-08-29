import Foundation

/// Talks to the backend's `GET /v1/work-hours` endpoint (see
/// `Sources/App/Controllers/WorkHoursController.swift`). A protocol so a
/// different implementation could stand in during previews/manual testing
/// without a running backend — no such fake exists in this package yet, but
/// the seam is here for one.
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
/// Transport (request construction, encoding/decoding, status validation) is
/// `PCCHTTPTransport`'s; this struct owns only its own endpoints and payload
/// shapes.
public struct URLSessionWorkHoursAPIClient: WorkHoursAPIClient {
    private let transport: PCCHTTPTransport

    public init(baseURL: URL, bearerToken: String, session: URLSession = .shared) {
        self.transport = PCCHTTPTransport(baseURL: baseURL, bearerToken: bearerToken, session: session)
    }

    public func fetchWorkHours(groupBy: WorkHoursGroupBy, start: Date, end: Date) async throws -> [WorkHoursRow] {
        // `start`/`end` are sent as plain ISO 8601 strings
        // (`PCCHTTPTransport`'s `.date` query value) — matching
        // `WorkHoursController.validatedRange`'s own hand-parsed query-date
        // format, not Vapor's query decoder's default of
        // seconds-since-1970.
        let request = try makeRequest(
            path: "v1/work-hours",
            method: "GET",
            query: ["groupBy": .string(groupBy.rawValue), "start": .date(start), "end": .date(end)]
        )
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
            unexpectedResponse: WorkHoursAPIClientError.unexpectedResponse,
            serverError: WorkHoursAPIClientError.serverError
        )
    }
}
