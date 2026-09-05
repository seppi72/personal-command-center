import Foundation

/// Talks to the backend's `/v1/personal-commitments` REST endpoints (see
/// `Sources/App/Controllers/PersonalCommitmentController.swift`). A protocol
/// so a different implementation could stand in during previews/manual
/// testing without a running backend — no such fake exists in this package
/// yet, but the seam is here for one.
public protocol PersonalCommitmentsAPIClient: Sendable {
    /// Lists every Commitment, or Commitments scoped to one Course when
    /// `courseID` is given (ticket #56). Every caller passes `nil` today —
    /// the screens that need a Course's Commitments (`SchoolViewModel`)
    /// filter the list they already loaded — but the parameter stays because
    /// it's this client's whole coverage of `GET
    /// /v1/personal-commitments?courseID=`, a backend filter that still
    /// exists, rather than an unused abstraction of our own (issue #98).
    func listPersonalCommitments(courseID: UUID?) async throws -> [PersonalCommitment]
    func createPersonalCommitment(_ values: PersonalCommitmentFormValues) async throws -> PersonalCommitment
    func updatePersonalCommitment(id: UUID, values: PersonalCommitmentFormValues) async throws -> PersonalCommitment
    func deletePersonalCommitment(id: UUID) async throws
}

public enum PersonalCommitmentsAPIClientError: Error {
    case unexpectedResponse
    case serverError(status: Int)
}

/// The real client: same bearer-token auth as every other route
/// (`BearerTokenAuthMiddleware`) — one token per device, issued out of band.
/// Transport (request construction, encoding/decoding, status validation) is
/// `PCCHTTPTransport`'s; this struct owns only its own endpoints and payload
/// shapes.
public struct URLSessionPersonalCommitmentsAPIClient: PersonalCommitmentsAPIClient {
    private let transport: PCCHTTPTransport

    public init(baseURL: URL, bearerToken: String, session: URLSession = .shared) {
        self.transport = PCCHTTPTransport(baseURL: baseURL, bearerToken: bearerToken, session: session)
    }

    public func listPersonalCommitments(courseID: UUID?) async throws -> [PersonalCommitment] {
        try await send(makeRequest(
            path: "v1/personal-commitments",
            method: "GET",
            query: ["courseID": courseID.map(PCCHTTPTransport.QueryValue.uuid)]
        ))
    }

    public func createPersonalCommitment(_ values: PersonalCommitmentFormValues) async throws -> PersonalCommitment {
        var request = try makeRequest(path: "v1/personal-commitments", method: "POST")
        try attach(SaveCommitmentPayload(values), to: &request)
        return try await send(request)
    }

    public func updatePersonalCommitment(
        id: UUID,
        values: PersonalCommitmentFormValues
    ) async throws -> PersonalCommitment {
        var request = try makeRequest(path: "v1/personal-commitments/\(id)", method: "PUT")
        try attach(SaveCommitmentPayload(values), to: &request)
        return try await send(request)
    }

    public func deletePersonalCommitment(id: UUID) async throws {
        let request = try makeRequest(path: "v1/personal-commitments/\(id)", method: "DELETE")
        try await sendNoBody(request)
    }

    private struct SaveCommitmentPayload: Encodable {
        let title: String
        let startDate: Date
        let endDate: Date
        let recurrenceRule: String?
        let courseID: UUID?

        init(_ values: PersonalCommitmentFormValues) {
            self.title = values.title
            self.startDate = values.startDate
            self.endDate = values.endDate
            self.recurrenceRule = values.recurrenceRule
            self.courseID = values.courseID
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
            unexpectedResponse: PersonalCommitmentsAPIClientError.unexpectedResponse,
            serverError: PersonalCommitmentsAPIClientError.serverError
        )
    }

    private func sendNoBody(_ request: URLRequest) async throws {
        try await transport.sendExpectingNoBody(
            request,
            unexpectedResponse: PersonalCommitmentsAPIClientError.unexpectedResponse,
            serverError: PersonalCommitmentsAPIClientError.serverError
        )
    }
}
