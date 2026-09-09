import Foundation

/// Talks to the backend's School Reporting endpoint (see
/// `Sources/App/Controllers/SchoolReportingController.swift`) — General
/// Weighted Average and Units Earned (`CONTEXT.md`). A protocol so a
/// different implementation could stand in during previews/manual testing
/// without a running backend — no such fake exists in this package yet, but
/// the seam is here for one.
public protocol SchoolReportingAPIClient: Sendable {
    /// Both figures. `termID` scopes only the per-Term GWA; the cumulative
    /// GWA and Units Earned are always over every Term.
    func fetchSchoolSummary(termID: UUID?) async throws -> SchoolSummary
}

public enum SchoolReportingAPIClientError: Error {
    case unexpectedResponse
    case serverError(status: Int)
}

/// The real client: same bearer-token auth as every other route
/// (`BearerTokenAuthMiddleware`) — one token per device, issued out of band.
/// Transport (request construction, encoding/decoding, status validation) is
/// `PCCHTTPTransport`'s; this struct owns only its own endpoint and payload
/// shape.
public struct URLSessionSchoolReportingAPIClient: SchoolReportingAPIClient {
    private let transport: PCCHTTPTransport

    public init(baseURL: URL, bearerToken: String, session: URLSession = .shared) {
        self.transport = PCCHTTPTransport(baseURL: baseURL, bearerToken: bearerToken, session: session)
    }

    public func fetchSchoolSummary(termID: UUID?) async throws -> SchoolSummary {
        let request = try transport.makeRequest(
            path: "v1/school-summary",
            method: "GET",
            query: ["termID": termID.map { .string($0.uuidString) }]
        )
        return try await transport.send(
            request,
            unexpectedResponse: SchoolReportingAPIClientError.unexpectedResponse,
            serverError: SchoolReportingAPIClientError.serverError
        )
    }
}
