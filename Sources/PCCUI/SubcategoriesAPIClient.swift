import Foundation

/// Talks to the backend's `/v1/subcategories` REST endpoints (see
/// `Sources/App/Controllers/SubcategoryController.swift`). A protocol so the
/// view model can be exercised against a fake in previews/manual testing
/// without a running backend.
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
public struct URLSessionSubcategoriesAPIClient: SubcategoriesAPIClient {
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

    public func listSubcategories(categoryID: UUID) async throws -> [Subcategory] {
        // `appendingPathComponent` (used by `makeRequest(path:method:)`)
        // percent-escapes "?", so a query string needs `URLComponents`
        // instead (mirrors `URLSessionSprintsAPIClient.listSprints`).
        var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/subcategories"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "categoryID", value: categoryID.uuidString)]
        guard let url = components?.url else {
            throw SubcategoriesAPIClientError.unexpectedResponse
        }
        return try await send(makeRequest(url: url, method: "GET"))
    }

    public func createSubcategory(categoryID: UUID, name: String) async throws -> Subcategory {
        var request = makeRequest(path: "v1/subcategories", method: "POST")
        try attach(SaveSubcategoryPayload(categoryID: categoryID, name: name), to: &request)
        return try await send(request)
    }

    public func updateSubcategory(id: UUID, name: String) async throws -> Subcategory {
        var request = makeRequest(path: "v1/subcategories/\(id)", method: "PUT")
        try attach(UpdateSubcategoryPayload(name: name), to: &request)
        return try await send(request)
    }

    public func deleteSubcategory(id: UUID) async throws {
        let request = makeRequest(path: "v1/subcategories/\(id)", method: "DELETE")
        let (_, response) = try await session.data(for: request)
        try Self.checkStatus(response)
    }

    private struct SaveSubcategoryPayload: Encodable {
        let categoryID: UUID
        let name: String
    }

    private struct UpdateSubcategoryPayload: Encodable {
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
        makeRequest(url: baseURL.appendingPathComponent(path), method: method)
    }

    private func makeRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func checkStatus(_ response: URLResponse) throws {
        try HTTPResponseValidation.checkStatus(
            response,
            unexpectedResponse: SubcategoriesAPIClientError.unexpectedResponse,
            serverError: SubcategoriesAPIClientError.serverError
        )
    }
}
