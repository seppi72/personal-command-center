import Foundation

/// Talks to the backend's `/v1/accounts` REST endpoints (see
/// `Sources/App/Controllers/AccountController.swift`). A protocol so the
/// view model can be exercised against a fake in previews/manual testing
/// without a running backend.
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
public struct URLSessionAccountsAPIClient: AccountsAPIClient {
    private let baseURL: URL
    private let bearerToken: String
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(baseURL: URL, bearerToken: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.bearerToken = bearerToken
        self.session = session
        self.decoder = JSONDecoder()
        // Matches the backend's `ContentConfiguration` (Vapor's default),
        // which encodes/decodes `Date` as an ISO 8601 string rather than
        // `JSONDecoder`'s own default of seconds-since-1970. `Account` has
        // no `Date` field today, but this keeps the same setup as every
        // other API client rather than a one-off exception.
        self.decoder.dateDecodingStrategy = .iso8601
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    public func listAccounts() async throws -> [Account] {
        let request = makeRequest(path: "v1/accounts", method: "GET")
        return try await send(request)
    }

    public func createAccount(name: String, type: AccountType, openingBalance: Double) async throws -> Account {
        var request = makeRequest(path: "v1/accounts", method: "POST")
        try attach(CreateAccountPayload(name: name, type: type, openingBalance: openingBalance), to: &request)
        return try await send(request)
    }

    public func updateAccount(id: UUID, name: String, type: AccountType) async throws -> Account {
        var request = makeRequest(path: "v1/accounts/\(id)", method: "PUT")
        try attach(UpdateAccountPayload(name: name, type: type), to: &request)
        return try await send(request)
    }

    public func deleteAccount(id: UUID) async throws {
        let request = makeRequest(path: "v1/accounts/\(id)", method: "DELETE")
        let (_, response) = try await session.data(for: request)
        try Self.checkStatus(response)
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

    private func attach<Body: Encodable>(_ body: Body, to request: inout URLRequest) throws {
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        try Self.checkStatus(response)
        return try decoder.decode(Response.self, from: data)
    }

    private func makeRequest(path: String, method: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func checkStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AccountsAPIClientError.unexpectedResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw AccountsAPIClientError.serverError(status: http.statusCode)
        }
    }
}
