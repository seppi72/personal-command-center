import Foundation

/// Talks to the backend's `/v1/time-entries` REST endpoints (see
/// `Sources/App/Controllers/TimeEntryController.swift`). A protocol so the
/// view model can be exercised against a fake in previews/manual testing
/// without a running backend.
public protocol TimeEntriesAPIClient: Sendable {
    /// Lists every Time Entry, or Time Entries scoped to one Task, Project,
    /// Client, and/or Course when the corresponding id is given.
    func listTimeEntries(taskID: UUID?, projectID: UUID?, clientID: UUID?, courseID: UUID?) async throws -> [TimeEntry]
    func createTimeEntry(_ values: TimeEntryFormValues) async throws -> TimeEntry
    func updateTimeEntry(id: UUID, values: TimeEntryFormValues) async throws -> TimeEntry
    func deleteTimeEntry(id: UUID) async throws
}

public enum TimeEntriesAPIClientError: Error {
    case unexpectedResponse
    case serverError(status: Int)
}

/// The real client: same bearer-token auth as every other route
/// (`BearerTokenAuthMiddleware`) — one token per device, issued out of band.
public struct URLSessionTimeEntriesAPIClient: TimeEntriesAPIClient {
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

    public func listTimeEntries(
        taskID: UUID?, projectID: UUID?, clientID: UUID?, courseID: UUID?
    ) async throws -> [TimeEntry] {
        // `appendingPathComponent` (used by `makeRequest`) percent-escapes
        // "?", so a query string needs `URLComponents` instead — same
        // reasoning as `TasksAPIClient.listTasks`.
        var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/time-entries"),
            resolvingAgainstBaseURL: false
        )
        var queryItems: [URLQueryItem] = []
        if let taskID {
            queryItems.append(URLQueryItem(name: "taskID", value: taskID.uuidString))
        }
        if let projectID {
            queryItems.append(URLQueryItem(name: "projectID", value: projectID.uuidString))
        }
        if let clientID {
            queryItems.append(URLQueryItem(name: "clientID", value: clientID.uuidString))
        }
        if let courseID {
            queryItems.append(URLQueryItem(name: "courseID", value: courseID.uuidString))
        }
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else {
            throw TimeEntriesAPIClientError.unexpectedResponse
        }
        return try await send(makeRequest(url: url, method: "GET"))
    }

    public func createTimeEntry(_ values: TimeEntryFormValues) async throws -> TimeEntry {
        var request = makeRequest(path: "v1/time-entries", method: "POST")
        try attach(SaveTimeEntryPayload(values), to: &request)
        return try await send(request)
    }

    public func updateTimeEntry(id: UUID, values: TimeEntryFormValues) async throws -> TimeEntry {
        var request = makeRequest(path: "v1/time-entries/\(id)", method: "PUT")
        try attach(SaveTimeEntryPayload(values), to: &request)
        return try await send(request)
    }

    public func deleteTimeEntry(id: UUID) async throws {
        let request = makeRequest(path: "v1/time-entries/\(id)", method: "DELETE")
        let (_, response) = try await session.data(for: request)
        try Self.checkStatus(response)
    }

    private struct SaveTimeEntryPayload: Encodable {
        let startDate: Date
        let endDate: Date
        let notes: String?
        let taskID: UUID?
        let projectID: UUID?
        let clientID: UUID?
        let courseID: UUID?

        init(_ values: TimeEntryFormValues) {
            self.startDate = values.startDate
            self.endDate = values.endDate
            self.notes = values.notes
            self.taskID = values.taskID
            self.projectID = values.projectID
            self.clientID = values.clientID
            self.courseID = values.courseID
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
            unexpectedResponse: TimeEntriesAPIClientError.unexpectedResponse,
            serverError: TimeEntriesAPIClientError.serverError
        )
    }
}
