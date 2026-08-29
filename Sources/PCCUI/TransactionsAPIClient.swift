import Foundation

/// Talks to the backend's `/v1/transactions` REST endpoints (see
/// `Sources/App/Controllers/TransactionController.swift`). A protocol so a
/// different implementation could stand in during previews/manual testing
/// without a running backend — no such fake exists in this package yet, but
/// the seam is here for one.
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
/// Transport (request construction, encoding/decoding, status validation) is
/// `PCCHTTPTransport`'s; this struct owns only its own endpoints and payload
/// shapes.
public struct URLSessionTransactionsAPIClient: TransactionsAPIClient {
    private let transport: PCCHTTPTransport

    public init(baseURL: URL, bearerToken: String, session: URLSession = .shared) {
        self.transport = PCCHTTPTransport(baseURL: baseURL, bearerToken: bearerToken, session: session)
    }

    public func listTransactions(accountID: UUID?, start: Date?, end: Date?) async throws -> [Transaction] {
        let request = try makeRequest(
            path: "v1/transactions",
            method: "GET",
            query: ["accountID": accountID.map(PCCHTTPTransport.QueryValue.uuid),
                    "start": start.map(PCCHTTPTransport.QueryValue.date),
                    "end": end.map(PCCHTTPTransport.QueryValue.date)]
        )
        return try await send(request)
    }

    public func createTransaction(_ values: TransactionFormValues) async throws -> Transaction {
        var request = try makeRequest(path: "v1/transactions", method: "POST")
        try attach(SaveTransactionPayload(values), to: &request)
        return try await send(request)
    }

    public func updateTransaction(id: UUID, values: TransactionFormValues) async throws -> Transaction {
        var request = try makeRequest(path: "v1/transactions/\(id)", method: "PUT")
        try attach(SaveTransactionPayload(values), to: &request)
        return try await send(request)
    }

    public func deleteTransaction(id: UUID) async throws {
        let request = try makeRequest(path: "v1/transactions/\(id)", method: "DELETE")
        try await sendNoBody(request)
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
            unexpectedResponse: TransactionsAPIClientError.unexpectedResponse,
            serverError: TransactionsAPIClientError.serverError
        )
    }

    private func sendNoBody(_ request: URLRequest) async throws {
        try await transport.sendExpectingNoBody(
            request,
            unexpectedResponse: TransactionsAPIClientError.unexpectedResponse,
            serverError: TransactionsAPIClientError.serverError
        )
    }
}
