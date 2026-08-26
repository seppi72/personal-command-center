import Foundation

/// Talks to the backend's `/v1/categories` REST endpoints (see
/// `Sources/App/Controllers/CategoryController.swift`). A protocol so the
/// view model can be exercised against a fake in previews/manual testing
/// without a running backend.
public protocol CategoriesAPIClient: Sendable {
    func listCategories() async throws -> [PCCCategory]
    func createCategory(name: String) async throws -> PCCCategory
    func updateCategory(id: UUID, name: String) async throws -> PCCCategory
    func deleteCategory(id: UUID) async throws
}

public enum CategoriesAPIClientError: Error {
    case unexpectedResponse
    case serverError(status: Int)
}

/// The real client: same bearer-token auth as every other route
/// (`BearerTokenAuthMiddleware`) — one token per device, issued out of band.
public struct URLSessionCategoriesAPIClient: CategoriesAPIClient {
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
        // `JSONDecoder`'s own default of seconds-since-1970. `PCCCategory`
        // has no `Date` field today, but this keeps the same setup as every
        // other API client rather than a one-off exception (mirrors
        // `URLSessionClientsAPIClient`).
        self.decoder.dateDecodingStrategy = .iso8601
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    public func listCategories() async throws -> [PCCCategory] {
        let request = makeRequest(path: "v1/categories", method: "GET")
        return try await send(request)
    }

    public func createCategory(name: String) async throws -> PCCCategory {
        var request = makeRequest(path: "v1/categories", method: "POST")
        try attach(SaveCategoryPayload(name: name), to: &request)
        return try await send(request)
    }

    public func updateCategory(id: UUID, name: String) async throws -> PCCCategory {
        var request = makeRequest(path: "v1/categories/\(id)", method: "PUT")
        try attach(SaveCategoryPayload(name: name), to: &request)
        return try await send(request)
    }

    public func deleteCategory(id: UUID) async throws {
        let request = makeRequest(path: "v1/categories/\(id)", method: "DELETE")
        let (_, response) = try await session.data(for: request)
        try Self.checkStatus(response)
    }

    private struct SaveCategoryPayload: Encodable {
        let name: String
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
        try HTTPResponseValidation.checkStatus(
            response,
            unexpectedResponse: CategoriesAPIClientError.unexpectedResponse,
            serverError: CategoriesAPIClientError.serverError
        )
    }
}
