import Foundation

/// Shared HTTP transport for this package's `URLSession`-backed API clients
/// (`URLSessionTasksAPIClient` and its 16 siblings): request construction,
/// bearer-token auth, JSON body encoding/decoding (ISO 8601 dates, matching
/// the backend's `ContentConfiguration`), query-string construction, and
/// status-code validation. Composed by each domain client as a private
/// property rather than inherited — Swift structs have no inheritance, and
/// composition keeps every domain client's own `Error` type and public
/// protocol untouched; only the transport plumbing behind them is shared.
///
/// Supersedes `HTTPResponseValidation` (ticket #7), which only shared the
/// status check — 5 of the 17 clients still carried their own copy of it,
/// and every client still hand-rolled `init`/`makeRequest`/`attach`/`send`
/// and, where it needed one, its own `URLComponents` query string. This is
/// the finished version of that extraction.
public struct PCCHTTPTransport: Sendable {
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
        self.decoder.dateDecodingStrategy = .iso8601
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    /// A query-string value. `.date` renders as a plain ISO 8601 string via
    /// `ISO8601DateFormatter` — matching every backend controller's own
    /// hand-parsed query-date format (e.g. `WorkHoursController.validatedRange`,
    /// `FinancesReportingController.validatedRange`) rather than
    /// `URLQueryItem`'s own `Date` handling.
    public enum QueryValue {
        case uuid(UUID)
        case date(Date)
        case string(String)
    }

    public enum TransportError: Error {
        case invalidQuery
    }

    /// Builds a request against `path` with bearer-token auth attached. When
    /// `query` has any non-`nil` value, builds a `URLComponents` query
    /// string instead of a plain path — `appendingPathComponent` alone
    /// percent-escapes "?", so a query string needs `URLComponents` (every
    /// prior client that built one carried this same comment). A `nil`
    /// value is dropped, not sent as an empty string — "omit the key" is
    /// every existing client's own "unfiltered" shape for an optional
    /// filter, preserved here.
    public func makeRequest(
        path: String,
        method: String,
        query: [String: QueryValue?] = [:]
    ) throws -> URLRequest {
        let presentQuery = query.compactMapValues { $0 }
        guard !presentQuery.isEmpty else {
            return makeRequest(url: baseURL.appendingPathComponent(path), method: method)
        }
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        // Built locally rather than stored on `self` — `ISO8601DateFormatter`
        // isn't `Sendable`, which a stored property on this `Sendable`
        // struct can't hold (same reasoning every prior client with a Date
        // query param already carried).
        let formatter = ISO8601DateFormatter()
        components?.queryItems = presentQuery.map { key, value in
            switch value {
            case .uuid(let id):
                return URLQueryItem(name: key, value: id.uuidString)
            case .date(let date):
                return URLQueryItem(name: key, value: formatter.string(from: date))
            case .string(let raw):
                return URLQueryItem(name: key, value: raw)
            }
        }
        guard let url = components?.url else {
            throw TransportError.invalidQuery
        }
        return makeRequest(url: url, method: method)
    }

    /// Builds a request against an already-assembled `url` — the escape
    /// hatch `makeRequest(path:method:query:)` itself uses once it has a
    /// final URL. Not `public`: no domain client needs it directly today: a
    /// real second caller can widen this later.
    func makeRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    public func attach<Body: Encodable>(_ body: Body, to request: inout URLRequest) throws {
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    /// Sends `request` and decodes its response body — the shape every
    /// non-DELETE, non-cancel call uses. `unexpectedResponse`/`serverError`
    /// let each domain client keep throwing its own `Error` type (its own
    /// `unexpectedResponse`/`serverError(status:)` cases) rather than this
    /// module owning one shared error type across every client.
    public func send<Response: Decodable>(
        _ request: URLRequest,
        unexpectedResponse: @autoclosure () -> any Error,
        serverError: (Int) -> any Error
    ) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        try checkStatus(response, unexpectedResponse: unexpectedResponse(), serverError: serverError)
        return try decoder.decode(Response.self, from: data)
    }

    /// Sends `request` and validates its status without decoding a body —
    /// DELETE and the timer's `cancel`, which return no content.
    public func sendExpectingNoBody(
        _ request: URLRequest,
        unexpectedResponse: @autoclosure () -> any Error,
        serverError: (Int) -> any Error
    ) async throws {
        let (_, response) = try await session.data(for: request)
        try checkStatus(response, unexpectedResponse: unexpectedResponse(), serverError: serverError)
    }

    /// Cast the response to `HTTPURLResponse`, then check its status is in
    /// the success range — every client needs exactly this before treating
    /// a response body as real data. Not `public`: only `send`/
    /// `sendExpectingNoBody` (and this target's own tests, via
    /// `@testable import`) call it directly.
    func checkStatus(
        _ response: URLResponse,
        unexpectedResponse: @autoclosure () -> any Error,
        serverError: (Int) -> any Error
    ) throws {
        guard let http = response as? HTTPURLResponse else {
            throw unexpectedResponse()
        }
        guard (200...299).contains(http.statusCode) else {
            throw serverError(http.statusCode)
        }
    }
}
