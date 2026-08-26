import Foundation

/// Talks to the backend's Finances Reporting endpoints (see
/// `Sources/App/Controllers/FinancesReportingController.swift`) — Net Worth
/// (current figure + trend), Account Balance history, expense-per-day, and
/// Projected Balance (`CONTEXT.md`). A protocol so the view model can be
/// exercised against a fake in previews/manual testing without a running
/// backend, the same seam every other `PCCUI` API client already has.
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
public struct URLSessionFinancesReportingAPIClient: FinancesReportingAPIClient {
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

    public func fetchCurrentNetWorth() async throws -> Double {
        let request = makeRequest(path: "v1/net-worth")
        let response: NetWorthPayload = try await send(request)
        return response.netWorth
    }

    public func fetchNetWorthTrend(start: Date, end: Date) async throws -> [DailyFigure] {
        let request = try makeRangeRequest(path: "v1/net-worth/trend", start: start, end: end)
        return try await send(request)
    }

    public func fetchAccountBalanceHistory(accountID: UUID, start: Date, end: Date) async throws -> [DailyFigure] {
        let request = try makeRangeRequest(path: "v1/accounts/\(accountID)/balance-history", start: start, end: end)
        return try await send(request)
    }

    public func fetchExpensesPerDay(start: Date, end: Date) async throws -> [ExpensesPerDayRow] {
        let request = try makeRangeRequest(path: "v1/expenses-per-day", start: start, end: end)
        return try await send(request)
    }

    public func fetchProjectedBalance(accountID: UUID, period: ProjectedBalancePeriod) async throws -> ProjectedBalance {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/accounts/\(accountID)/projected-balance"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "period", value: period.rawValue)]
        guard let url = components?.url else {
            throw FinancesReportingAPIClientError.unexpectedResponse
        }
        return try await send(makeRequest(url: url))
    }

    private struct NetWorthPayload: Decodable {
        let netWorth: Double
    }

    /// `start`/`end` are formatted as plain ISO 8601 strings via
    /// `URLComponents`/`URLQueryItem`, not left to `URLQueryItem`'s own
    /// `Date` handling — same `WorkHoursController.validatedRange` reasoning
    /// this client shares with `URLSessionWorkHoursAPIClient`:
    /// `FinancesReportingController.validatedRange` parses the query string
    /// by hand with `ISO8601DateFormatter`, not Vapor's query decoder's own
    /// seconds-since-1970 default. `appendingPathComponent` alone (used for
    /// a plain path elsewhere in this client) percent-escapes "?", so a query
    /// string needs `URLComponents` instead.
    private func makeRangeRequest(path: String, start: Date, end: Date) throws -> URLRequest {
        // Built locally rather than stored on `self` — `ISO8601DateFormatter`
        // doesn't conform to `Sendable` (same reasoning
        // `URLSessionWorkHoursAPIClient.fetchWorkHours` already has for its
        // own local formatter), which a stored property on this
        // `Sendable`-conforming struct can't hold.
        let formatter = ISO8601DateFormatter()
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "start", value: formatter.string(from: start)),
            URLQueryItem(name: "end", value: formatter.string(from: end)),
        ]
        guard let url = components?.url else {
            throw FinancesReportingAPIClientError.unexpectedResponse
        }
        return makeRequest(url: url)
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        try HTTPResponseValidation.checkStatus(
            response,
            unexpectedResponse: FinancesReportingAPIClientError.unexpectedResponse,
            serverError: FinancesReportingAPIClientError.serverError
        )
        return try decoder.decode(Response.self, from: data)
    }

    private func makeRequest(path: String) -> URLRequest {
        makeRequest(url: baseURL.appendingPathComponent(path))
    }

    private func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        return request
    }
}
