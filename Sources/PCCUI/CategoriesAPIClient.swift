import Foundation

/// Talks to the backend's `/v1/categories` REST endpoints (see
/// `Sources/App/Controllers/CategoryController.swift`). A protocol so a
/// different implementation could stand in during previews/manual testing
/// without a running backend — no such fake exists in this package yet, but
/// the seam is here for one.
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
/// Transport (request construction, encoding/decoding, status validation) is
/// `PCCHTTPTransport`'s; this struct owns only its own endpoints and payload
/// shapes.
public struct URLSessionCategoriesAPIClient: CategoriesAPIClient {
    private let transport: PCCHTTPTransport

    public init(baseURL: URL, bearerToken: String, session: URLSession = .shared) {
        self.transport = PCCHTTPTransport(baseURL: baseURL, bearerToken: bearerToken, session: session)
    }

    public func listCategories() async throws -> [PCCCategory] {
        let request = try makeRequest(path: "v1/categories", method: "GET")
        return try await send(request)
    }

    public func createCategory(name: String) async throws -> PCCCategory {
        var request = try makeRequest(path: "v1/categories", method: "POST")
        try attach(SaveCategoryPayload(name: name), to: &request)
        return try await send(request)
    }

    public func updateCategory(id: UUID, name: String) async throws -> PCCCategory {
        var request = try makeRequest(path: "v1/categories/\(id)", method: "PUT")
        try attach(SaveCategoryPayload(name: name), to: &request)
        return try await send(request)
    }

    public func deleteCategory(id: UUID) async throws {
        let request = try makeRequest(path: "v1/categories/\(id)", method: "DELETE")
        try await sendNoBody(request)
    }

    private struct SaveCategoryPayload: Encodable {
        let name: String
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
            unexpectedResponse: CategoriesAPIClientError.unexpectedResponse,
            serverError: CategoriesAPIClientError.serverError
        )
    }

    private func sendNoBody(_ request: URLRequest) async throws {
        try await transport.sendExpectingNoBody(
            request,
            unexpectedResponse: CategoriesAPIClientError.unexpectedResponse,
            serverError: CategoriesAPIClientError.serverError
        )
    }
}
