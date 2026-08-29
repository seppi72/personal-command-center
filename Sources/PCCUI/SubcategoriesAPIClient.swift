import Foundation

/// Talks to the backend's `/v1/subcategories` REST endpoints (see
/// `Sources/App/Controllers/SubcategoryController.swift`). A protocol so a
/// different implementation could stand in during previews/manual testing
/// without a running backend — no such fake exists in this package yet, but
/// the seam is here for one.
public protocol SubcategoriesAPIClient: Sendable {
    /// A Subcategory has no meaning outside a Category, so listing is
    /// always scoped to one — there's no "list all Subcategories" call,
    /// mirroring `SprintsAPIClient.listSprints`.
    func listSubcategories(categoryID: UUID) async throws -> [Subcategory]
    func createSubcategory(categoryID: UUID, name: String) async throws -> Subcategory
    func updateSubcategory(id: UUID, name: String) async throws -> Subcategory
    func deleteSubcategory(id: UUID) async throws
}

public enum SubcategoriesAPIClientError: Error {
    case unexpectedResponse
    case serverError(status: Int)
}

/// The real client: same bearer-token auth as every other route
/// (`BearerTokenAuthMiddleware`) — one token per device, issued out of band.
/// Transport (request construction, encoding/decoding, status validation) is
/// `PCCHTTPTransport`'s; this struct owns only its own endpoints and payload
/// shapes.
public struct URLSessionSubcategoriesAPIClient: SubcategoriesAPIClient {
    private let transport: PCCHTTPTransport

    public init(baseURL: URL, bearerToken: String, session: URLSession = .shared) {
        self.transport = PCCHTTPTransport(baseURL: baseURL, bearerToken: bearerToken, session: session)
    }

    public func listSubcategories(categoryID: UUID) async throws -> [Subcategory] {
        let request = try makeRequest(
            path: "v1/subcategories",
            method: "GET",
            query: ["categoryID": .uuid(categoryID)]
        )
        return try await send(request)
    }

    public func createSubcategory(categoryID: UUID, name: String) async throws -> Subcategory {
        var request = try makeRequest(path: "v1/subcategories", method: "POST")
        try attach(SaveSubcategoryPayload(categoryID: categoryID, name: name), to: &request)
        return try await send(request)
    }

    public func updateSubcategory(id: UUID, name: String) async throws -> Subcategory {
        var request = try makeRequest(path: "v1/subcategories/\(id)", method: "PUT")
        try attach(UpdateSubcategoryPayload(name: name), to: &request)
        return try await send(request)
    }

    public func deleteSubcategory(id: UUID) async throws {
        let request = try makeRequest(path: "v1/subcategories/\(id)", method: "DELETE")
        try await sendNoBody(request)
    }

    private struct SaveSubcategoryPayload: Encodable {
        let categoryID: UUID
        let name: String
    }

    private struct UpdateSubcategoryPayload: Encodable {
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
            unexpectedResponse: SubcategoriesAPIClientError.unexpectedResponse,
            serverError: SubcategoriesAPIClientError.serverError
        )
    }

    private func sendNoBody(_ request: URLRequest) async throws {
        try await transport.sendExpectingNoBody(
            request,
            unexpectedResponse: SubcategoriesAPIClientError.unexpectedResponse,
            serverError: SubcategoriesAPIClientError.serverError
        )
    }
}
