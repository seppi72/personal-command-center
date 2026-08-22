import Foundation

/// Talks to the backend's `/v1/personal-commitments` REST endpoints (see
/// `Sources/App/Controllers/PersonalCommitmentController.swift`). A
/// protocol so the view model can be exercised against a fake in
/// previews/manual testing without a running backend.
public protocol PersonalCommitmentsAPIClient: Sendable {
    func listPersonalCommitments() async throws -> [PersonalCommitment]
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
public struct URLSessionPersonalCommitmentsAPIClient: PersonalCommitmentsAPIClient {
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
        // `JSONDecoder`'s own default of seconds-since-1970.
        self.decoder.dateDecodingStrategy = .iso8601
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    public func listPersonalCommitments() async throws -> [PersonalCommitment] {
        try await send(makeRequest(path: "v1/personal-commitments", method: "GET"))
    }

    public func createPersonalCommitment(_ values: PersonalCommitmentFormValues) async throws -> PersonalCommitment {
        var request = makeRequest(path: "v1/personal-commitments", method: "POST")
        try attach(SaveCommitmentPayload(values), to: &request)
        return try await send(request)
    }

    public func updatePersonalCommitment(
        id: UUID,
        values: PersonalCommitmentFormValues
    ) async throws -> PersonalCommitment {
        var request = makeRequest(path: "v1/personal-commitments/\(id)", method: "PUT")
        try attach(SaveCommitmentPayload(values), to: &request)
        return try await send(request)
    }

    public func deletePersonalCommitment(id: UUID) async throws {
        let request = makeRequest(path: "v1/personal-commitments/\(id)", method: "DELETE")
        let (_, response) = try await session.data(for: request)
        try Self.checkStatus(response)
    }

    private struct SaveCommitmentPayload: Encodable {
        let title: String
        let startDate: Date
        let endDate: Date
        let recurrenceRule: String?

        init(_ values: PersonalCommitmentFormValues) {
            self.title = values.title
            self.startDate = values.startDate
            self.endDate = values.endDate
            self.recurrenceRule = values.recurrenceRule
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
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func checkStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw PersonalCommitmentsAPIClientError.unexpectedResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw PersonalCommitmentsAPIClientError.serverError(status: http.statusCode)
        }
    }
}
