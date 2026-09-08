import Foundation

/// Talks to the backend's `/v1/terms` REST endpoints (see
/// `Sources/App/Controllers/TermController.swift`). A protocol for the same
/// reason `CoursesAPIClient` is one — a fake could stand in for previews
/// without a running backend.
public protocol TermsAPIClient: Sendable {
    func listTerms() async throws -> [Term]
    func createTerm(year: Int, semester: Semester, startDate: Date?, endDate: Date?) async throws -> Term
    func updateTerm(id: UUID, year: Int, semester: Semester, startDate: Date?, endDate: Date?) async throws -> Term
    func deleteTerm(id: UUID) async throws
}

public enum TermsAPIClientError: Error {
    case unexpectedResponse
    case serverError(status: Int)
}

/// The real client: same bearer-token auth and `PCCHTTPTransport` plumbing
/// as every other endpoint group.
public struct URLSessionTermsAPIClient: TermsAPIClient {
    private let transport: PCCHTTPTransport

    public init(baseURL: URL, bearerToken: String, session: URLSession = .shared) {
        self.transport = PCCHTTPTransport(baseURL: baseURL, bearerToken: bearerToken, session: session)
    }

    public func listTerms() async throws -> [Term] {
        let request = try makeRequest(path: "v1/terms", method: "GET")
        return try await send(request)
    }

    public func createTerm(
        year: Int, semester: Semester, startDate: Date?, endDate: Date?
    ) async throws -> Term {
        var request = try makeRequest(path: "v1/terms", method: "POST")
        try attach(
            SaveTermPayload(year: year, semester: semester, startDate: startDate, endDate: endDate),
            to: &request)
        return try await send(request)
    }

    public func updateTerm(
        id: UUID, year: Int, semester: Semester, startDate: Date?, endDate: Date?
    ) async throws -> Term {
        var request = try makeRequest(path: "v1/terms/\(id)", method: "PUT")
        try attach(
            SaveTermPayload(year: year, semester: semester, startDate: startDate, endDate: endDate),
            to: &request)
        return try await send(request)
    }

    public func deleteTerm(id: UUID) async throws {
        let request = try makeRequest(path: "v1/terms/\(id)", method: "DELETE")
        try await sendNoBody(request)
    }

    private struct SaveTermPayload: Encodable {
        let year: Int
        let semester: Semester
        let startDate: Date?
        let endDate: Date?
    }

    private func makeRequest(path: String, method: String) throws -> URLRequest {
        try transport.makeRequest(path: path, method: method)
    }

    private func attach<Body: Encodable>(_ body: Body, to request: inout URLRequest) throws {
        try transport.attach(body, to: &request)
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        try await transport.send(
            request,
            unexpectedResponse: TermsAPIClientError.unexpectedResponse,
            serverError: TermsAPIClientError.serverError
        )
    }

    private func sendNoBody(_ request: URLRequest) async throws {
        try await transport.sendExpectingNoBody(
            request,
            unexpectedResponse: TermsAPIClientError.unexpectedResponse,
            serverError: TermsAPIClientError.serverError
        )
    }
}
