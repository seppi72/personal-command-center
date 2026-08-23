import Foundation

/// Shared HTTP status-code validation for this package's `URLSession`-backed
/// API clients: cast the response to `HTTPURLResponse`, then check its
/// status is in the success range. Every client needs exactly this before
/// treating a response body as real data — factored out here (ticket #7)
/// rather than `URLSessionMirroredCalendarEventsAPIClient` growing a second
/// hand-written copy of the check `URLSessionPersonalCommitmentsAPIClient`
/// already had. Each client keeps throwing its own `Error` type (its own
/// `unexpectedResponse`/`serverError(status:)` cases), so callers still
/// catch the same per-client error enum they already do — only the check
/// itself is shared, not the error type.
enum HTTPResponseValidation {
    static func checkStatus(
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
