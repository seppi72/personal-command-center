import Foundation

/// Talks to the backend's read-only `/v1/automation-logs` endpoint (see
/// `Sources/App/Controllers/AutomationLogController.swift`). A protocol so a
/// different implementation could stand in during previews/manual testing
/// without a running backend — no such fake exists in this package yet, but
/// the seam is here for one. No create/update/delete methods — the log
/// isn't owner-editable.
public protocol AutomationLogsAPIClient: Sendable {
    func listAutomationLogs() async throws -> AutomationLogsPage
}

public enum AutomationLogsAPIClientError: Error {
    case unexpectedResponse
    case serverError(status: Int)
}

/// The real client: same bearer-token auth as every other route
/// (`BearerTokenAuthMiddleware`) — one token per device, issued out of band.
/// Transport (request construction, encoding/decoding, status validation) is
/// `PCCHTTPTransport`'s; this struct owns only its own endpoints and payload
/// shapes.
public struct URLSessionAutomationLogsAPIClient: AutomationLogsAPIClient {
    private let transport: PCCHTTPTransport

    public init(baseURL: URL, bearerToken: String, session: URLSession = .shared) {
        self.transport = PCCHTTPTransport(baseURL: baseURL, bearerToken: bearerToken, session: session)
    }

    public func listAutomationLogs() async throws -> AutomationLogsPage {
        let request = try makeRequest(path: "v1/automation-logs", method: "GET")
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
            unexpectedResponse: AutomationLogsAPIClientError.unexpectedResponse,
            serverError: AutomationLogsAPIClientError.serverError
        )
    }
}
