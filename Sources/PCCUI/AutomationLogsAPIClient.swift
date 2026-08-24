import Foundation

/// Talks to the backend's read-only `/v1/automation-logs` endpoint (see
/// `Sources/App/Controllers/AutomationLogController.swift`). A protocol so
/// the view model can be exercised against a fake in previews/manual testing
/// without a running backend. No create/update/delete methods — the log
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
public struct URLSessionAutomationLogsAPIClient: AutomationLogsAPIClient {
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

    public func listAutomationLogs() async throws -> AutomationLogsPage {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/automation-logs"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try HTTPResponseValidation.checkStatus(
            response,
            unexpectedResponse: AutomationLogsAPIClientError.unexpectedResponse,
            serverError: AutomationLogsAPIClientError.serverError
        )
        return try decoder.decode(AutomationLogsPage.self, from: data)
    }
}
