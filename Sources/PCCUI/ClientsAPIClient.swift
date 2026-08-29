import Foundation

/// Talks to the backend's `/v1/clients` REST endpoints (see
/// `Sources/App/Controllers/ClientController.swift`). A protocol so a
/// different implementation could stand in during previews/manual testing
/// without a running backend — no such fake exists in this package yet, but
/// the seam is here for one.
public protocol ClientsAPIClient: Sendable {
    func listClients() async throws -> [PCCClient]
    func createClient(name: String) async throws -> PCCClient
    func updateClient(id: UUID, name: String) async throws -> PCCClient
    func deleteClient(id: UUID) async throws
}

public enum ClientsAPIClientError: Error {
    case unexpectedResponse
    case serverError(status: Int)
}

/// The real client: same bearer-token auth as every other route
/// (`BearerTokenAuthMiddleware`) — one token per device, issued out of band.
/// Transport (request construction, encoding/decoding, status validation) is
/// `PCCHTTPTransport`'s; this struct owns only its own endpoints and payload
/// shapes.
public struct URLSessionClientsAPIClient: ClientsAPIClient {
    private let transport: PCCHTTPTransport

    public init(baseURL: URL, bearerToken: String, session: URLSession = .shared) {
        self.transport = PCCHTTPTransport(baseURL: baseURL, bearerToken: bearerToken, session: session)
    }

    public func listClients() async throws -> [PCCClient] {
        let request = try makeRequest(path: "v1/clients", method: "GET")
        return try await send(request)
    }

    public func createClient(name: String) async throws -> PCCClient {
        var request = try makeRequest(path: "v1/clients", method: "POST")
        try attach(SaveClientPayload(name: name), to: &request)
        return try await send(request)
    }

    public func updateClient(id: UUID, name: String) async throws -> PCCClient {
        var request = try makeRequest(path: "v1/clients/\(id)", method: "PUT")
        try attach(SaveClientPayload(name: name), to: &request)
        return try await send(request)
    }

    public func deleteClient(id: UUID) async throws {
        let request = try makeRequest(path: "v1/clients/\(id)", method: "DELETE")
        try await sendNoBody(request)
    }

    private struct SaveClientPayload: Encodable {
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
            unexpectedResponse: ClientsAPIClientError.unexpectedResponse,
            serverError: ClientsAPIClientError.serverError
        )
    }

    private func sendNoBody(_ request: URLRequest) async throws {
        try await transport.sendExpectingNoBody(
            request,
            unexpectedResponse: ClientsAPIClientError.unexpectedResponse,
            serverError: ClientsAPIClientError.serverError
        )
    }
}
