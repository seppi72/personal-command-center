import Foundation

/// Talks to the backend's `/v1/transactions` REST endpoints (see
/// `Sources/App/Controllers/TransactionController.swift`). A protocol so the
/// view model can be exercised against a fake in previews/manual testing
/// without a running backend.
public protocol TransactionsAPIClient: Sendable {
    /// Lists every Transaction, or Transactions scoped to one Account
    /// and/or a `[start, end)` date range when the corresponding value is
    /// given — combinable filters, mirroring
    /// `TimeEntriesAPIClient.listTimeEntries`.
    func listTransactions(accountID: UUID?, start: Date?, end: Date?) async throws -> [Transaction]
    func createTransaction(_ values: TransactionFormValues) async throws -> Transaction
    func updateTransaction(id: UUID, values: TransactionFormValues) async throws -> Transaction
    func deleteTransaction(id: UUID) async throws
}

public enum TransactionsAPIClientError: Error {
    case unexpectedResponse
    case serverError(status: Int)
    /// `createTransaction`/`updateTransaction` were called with
    /// `values.accountID == nil` — shouldn't happen in practice, since
    /// `TransactionFormSheet` disables Save until an Account is picked, but
    /// caught here rather than left as a crash for any future caller of
    /// this client that skips that gate.
    case missingAccount
}

/// The real client: same bearer-token auth as every other route
/// (`BearerTokenAuthMiddleware`) — one token per device, issued out of band.
public struct URLSessionTransactionsAPIClient: TransactionsAPIClient {
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
        // which encodes/decodes a JSON body's `Date` as an ISO 8601 string
        // rather than `JSONDecoder`'s own default of seconds-since-1970.
        self.decoder.dateDecodingStrategy = .iso8601
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    public func listTransactions(accountID: UUID?, start: Date?, end: Date?) async throws -> [Transaction] {
        // `appendingPathComponent` (used by `makeRequest`) percent-escapes
        // "?", so a query string needs `URLComponents` instead — same
        // reasoning as `TimeEntriesAPIClient.listTimeEntries`. `start`/`end`
        // are formatted as plain ISO 8601 strings, matching
        // `TransactionController.validatedQueryDate`'s own hand-parsed
        // format rather than `URLQueryItem`'s own `Date` handling.
        var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/transactions"),
            resolvingAgainstBaseURL: false
        )
        var queryItems: [URLQueryItem] = []
        if let accountID {
            queryItems.append(URLQueryItem(name: "accountID", value: accountID.uuidString))
        }
        let formatter = ISO8601DateFormatter()
        if let start {
            queryItems.append(URLQueryItem(name: "start", value: formatter.string(from: start)))
        }
        if let end {
            queryItems.append(URLQueryItem(name: "end", value: formatter.string(from: end)))
        }
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else {
            throw TransactionsAPIClientError.unexpectedResponse
        }
        return try await send(makeRequest(url: url, method: "GET"))
    }

    public func createTransaction(_ values: TransactionFormValues) async throws -> Transaction {
        var request = makeRequest(path: "v1/transactions", method: "POST")
        try attach(SaveTransactionPayload(values), to: &request)
        return try await send(request)
    }

    public func updateTransaction(id: UUID, values: TransactionFormValues) async throws -> Transaction {
        var request = makeRequest(path: "v1/transactions/\(id)", method: "PUT")
        try attach(SaveTransactionPayload(values), to: &request)
        return try await send(request)
    }

    public func deleteTransaction(id: UUID) async throws {
        let request = makeRequest(path: "v1/transactions/\(id)", method: "DELETE")
        let (_, response) = try await session.data(for: request)
        try Self.checkStatus(response)
    }

    /// `accountID` is required on the wire (`SaveTransactionRequest`'s own
    /// non-optional `accountID`), where `TransactionFormValues.accountID`
    /// is optional — `nil` only transiently, before the owner has picked
    /// one. `TransactionFormSheet` never calls `onSave` while it's still
    /// `nil` (Save stays disabled until then), but this bridges the two
    /// shapes with a thrown error rather than a force-unwrap, so a future
    /// caller that skips that gate fails cleanly instead of crashing.
    private struct SaveTransactionPayload: Encodable {
        let accountID: UUID
        let amount: Double
        let type: TransactionType
        let date: Date
        let notes: String?
        let categoryID: UUID?
        let subcategoryID: UUID?

        init(_ values: TransactionFormValues) throws {
            guard let accountID = values.accountID else {
                throw TransactionsAPIClientError.missingAccount
            }
            self.accountID = accountID
            self.amount = values.amount
            self.type = values.type
            self.date = values.date
            self.notes = values.notes
            self.categoryID = values.categoryID
            self.subcategoryID = values.subcategoryID
        }
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
        makeRequest(url: baseURL.appendingPathComponent(path), method: method)
    }

    private func makeRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func checkStatus(_ response: URLResponse) throws {
        try HTTPResponseValidation.checkStatus(
            response,
            unexpectedResponse: TransactionsAPIClientError.unexpectedResponse,
            serverError: TransactionsAPIClientError.serverError
        )
    }
}
