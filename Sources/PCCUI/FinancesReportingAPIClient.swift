import Foundation

/// Talks to the backend's Finances Reporting endpoints (see
/// `Sources/App/Controllers/FinancesReportingController.swift`) — Net Worth
/// (current figure + trend), Account Balance history, expense-per-day, and
/// Projected Balance (`CONTEXT.md`). A protocol so a different
/// implementation could stand in during previews/manual testing without a
/// running backend — no such fake exists in this package yet, but the seam
/// is here for one.
public protocol FinancesReportingAPIClient: Sendable {
    /// The current Net Worth figure, computed live.
    func fetchCurrentNetWorth() async throws -> Double
    /// The Net Worth trend over `[start, end)`, one dense row per day.
    func fetchNetWorthTrend(start: Date, end: Date) async throws -> [DailyFigure]
    /// One Account's Balance over `[start, end)`, one dense row per day.
    func fetchAccountBalanceHistory(accountID: UUID, start: Date, end: Date) async throws -> [DailyFigure]
    /// Expense totals over `[start, end)`, one dense row per day, across
    /// every Account regardless of Type.
    func fetchExpensesPerDay(start: Date, end: Date) async throws -> [ExpensesPerDayRow]
    /// One Account's Projected Balance for `period`.
    func fetchProjectedBalance(accountID: UUID, period: ProjectedBalancePeriod) async throws -> ProjectedBalance
}

public enum FinancesReportingAPIClientError: Error {
    case unexpectedResponse
    case serverError(status: Int)
}

/// The real client: same bearer-token auth as every other route
/// (`BearerTokenAuthMiddleware`) — one token per device, issued out of band.
/// Transport (request construction, encoding/decoding, status validation) is
/// `PCCHTTPTransport`'s; this struct owns only its own endpoints and payload
/// shapes.
public struct URLSessionFinancesReportingAPIClient: FinancesReportingAPIClient {
    private let transport: PCCHTTPTransport

    public init(baseURL: URL, bearerToken: String, session: URLSession = .shared) {
        self.transport = PCCHTTPTransport(baseURL: baseURL, bearerToken: bearerToken, session: session)
    }

    public func fetchCurrentNetWorth() async throws -> Double {
        let request = try makeRequest(path: "v1/net-worth", method: "GET")
        let response: NetWorthPayload = try await send(request)
        return response.netWorth
    }

    public func fetchNetWorthTrend(start: Date, end: Date) async throws -> [DailyFigure] {
        try await send(makeRangeRequest(path: "v1/net-worth/trend", start: start, end: end))
    }

    public func fetchAccountBalanceHistory(accountID: UUID, start: Date, end: Date) async throws -> [DailyFigure] {
        try await send(makeRangeRequest(path: "v1/accounts/\(accountID)/balance-history", start: start, end: end))
    }

    public func fetchExpensesPerDay(start: Date, end: Date) async throws -> [ExpensesPerDayRow] {
        try await send(makeRangeRequest(path: "v1/expenses-per-day", start: start, end: end))
    }

    public func fetchProjectedBalance(accountID: UUID, period: ProjectedBalancePeriod) async throws -> ProjectedBalance {
        let request = try makeRequest(
            path: "v1/accounts/\(accountID)/projected-balance",
            method: "GET",
            query: ["period": .string(period.rawValue)]
        )
        return try await send(request)
    }

    private struct NetWorthPayload: Decodable {
        let netWorth: Double
    }

    /// `start`/`end` are sent as plain ISO 8601 strings (`PCCHTTPTransport`'s
    /// `.date` query value) — matching `FinancesReportingController.validatedRange`'s
    /// own hand-parsed query-date format, the same reasoning
    /// `WorkHoursController.validatedRange`/`URLSessionWorkHoursAPIClient`
    /// share.
    private func makeRangeRequest(path: String, start: Date, end: Date) throws -> URLRequest {
        try makeRequest(path: path, method: "GET", query: ["start": .date(start), "end": .date(end)])
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
            unexpectedResponse: FinancesReportingAPIClientError.unexpectedResponse,
            serverError: FinancesReportingAPIClientError.serverError
        )
    }
}
