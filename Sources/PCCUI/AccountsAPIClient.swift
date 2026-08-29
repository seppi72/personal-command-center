import Foundation

/// Talks to the backend's `/v1/accounts` REST endpoints (see
/// `Sources/App/Controllers/AccountController.swift`). A protocol so a
/// different implementation could stand in during previews/manual testing
/// without a running backend — no such fake exists in this package yet, but
/// the seam is here for one.
///
/// `updateAccount` takes no `openingBalance` parameter at all — matching
/// `UpdateAccountRequest`'s own shape, `openingBalance` is immutable after
/// creation (`docs/adr/0007-computed-balance-over-reconciliation.md`) and
/// there is no wire path here that could send one.
public protocol AccountsAPIClient: Sendable {
    func listAccounts() async throws -> [Account]
    func createAccount(name: String, type: AccountType, openingBalance: Double) async throws -> Account
    func updateAccount(id: UUID, name: String, type: AccountType) async throws -> Account
    func deleteAccount(id: UUID) async throws
}

public enum AccountsAPIClientError: Error {
    case unexpectedResponse
    case serverError(status: Int)
}

/// The real client: same bearer-token auth as every other route
/// (`BearerTokenAuthMiddleware`) — one token per device, issued out of band.
/// Transport (request construction, encoding/decoding, status validation) is
/// `PCCHTTPTransport`'s; this struct owns only its own endpoints and payload
/// shapes.
public struct URLSessionAccountsAPIClient: AccountsAPIClient {
    private let transport: PCCHTTPTransport

    public init(baseURL: URL, bearerToken: String, session: URLSession = .shared) {
        self.transport = PCCHTTPTransport(baseURL: baseURL, bearerToken: bearerToken, session: session)
    }

    public func listAccounts() async throws -> [Account] {
        let request = try makeRequest(path: "v1/accounts", method: "GET")
        return try await send(request)
    }

    public func createAccount(name: String, type: AccountType, openingBalance: Double) async throws -> Account {
        var request = try makeRequest(path: "v1/accounts", method: "POST")
        try attach(CreateAccountPayload(name: name, type: type, openingBalance: openingBalance), to: &request)
        return try await send(request)
    }

    public func updateAccount(id: UUID, name: String, type: AccountType) async throws -> Account {
        var request = try makeRequest(path: "v1/accounts/\(id)", method: "PUT")
        try attach(UpdateAccountPayload(name: name, type: type), to: &request)
        return try await send(request)
    }

    public func deleteAccount(id: UUID) async throws {
        let request = try makeRequest(path: "v1/accounts/\(id)", method: "DELETE")
        try await sendNoBody(request)
    }

    private struct CreateAccountPayload: Encodable {
        let name: String
        let type: AccountType
        let openingBalance: Double
    }

    private struct UpdateAccountPayload: Encodable {
        let name: String
        let type: AccountType
    }

    private func makeRequest(
        path: String,
        method: String,
        query: [String: PCCHTTPTransport.QueryValue?] = [:]
    ) throws -> URLRequest {
        try transport.makeRequest(path: path, method: method, query: query)
    }

    private func attach<Body: Encodable>(_ body: Body, to request: inout URLRequest) throws {
        try transport.attach(body, to: &request)
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        try await transport.send(
            request,
            unexpectedResponse: AccountsAPIClientError.unexpectedResponse,
            serverError: AccountsAPIClientError.serverError
        )
    }

    private func sendNoBody(_ request: URLRequest) async throws {
        try await transport.sendExpectingNoBody(
            request,
            unexpectedResponse: AccountsAPIClientError.unexpectedResponse,
            serverError: AccountsAPIClientError.serverError
        )
    }
}
