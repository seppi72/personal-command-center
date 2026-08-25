import Foundation

/// Talks to the backend's `/v1/tasks` REST endpoints (see
/// `Sources/App/Controllers/TaskController.swift`). A protocol so the view
/// model can be exercised against a fake in previews/manual testing without
/// a running backend.
public protocol TasksAPIClient: Sendable {
    /// Lists every Task, or Tasks scoped to one Project and/or one Course
    /// when `projectID`/`courseID` are given.
    func listTasks(projectID: UUID?, courseID: UUID?) async throws -> [PCCTask]
    func createTask(title: String, notes: String?) async throws -> PCCTask
    func updateTask(id: UUID, title: String, notes: String?) async throws -> PCCTask
    func deleteTask(id: UUID) async throws
    func setTaskCompletion(id: UUID, isComplete: Bool) async throws -> PCCTask
    /// Assigns, moves, or removes (`projectID: nil`) a Task's Project.
    func assignTaskProject(id: UUID, projectID: UUID?) async throws -> PCCTask
    /// Attaches, changes, or removes (`dueDate: nil`) a Task's Deadline.
    func setTaskDeadline(id: UUID, dueDate: Date?) async throws -> PCCTask
    /// Assigns, moves, or removes (`courseID: nil`) a Task's Course.
    func assignTaskCourse(id: UUID, courseID: UUID?) async throws -> PCCTask
}

public enum TasksAPIClientError: Error {
    case unexpectedResponse
    case serverError(status: Int)
}

/// The real client: same bearer-token auth as every other route
/// (`BearerTokenAuthMiddleware`) — one token per device, issued out of band.
public struct URLSessionTasksAPIClient: TasksAPIClient {
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

    public func listTasks(projectID: UUID?, courseID: UUID?) async throws -> [PCCTask] {
        // `appendingPathComponent` (used by `makeRequest`) percent-escapes
        // "?", so a query string needs `URLComponents` instead.
        var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/tasks"),
            resolvingAgainstBaseURL: false
        )
        var queryItems: [URLQueryItem] = []
        if let projectID {
            queryItems.append(URLQueryItem(name: "projectID", value: projectID.uuidString))
        }
        if let courseID {
            queryItems.append(URLQueryItem(name: "courseID", value: courseID.uuidString))
        }
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else {
            throw TasksAPIClientError.unexpectedResponse
        }
        return try await send(makeRequest(url: url, method: "GET"))
    }

    public func createTask(title: String, notes: String?) async throws -> PCCTask {
        var request = makeRequest(path: "v1/tasks", method: "POST")
        try attach(SaveTaskPayload(title: title, notes: notes), to: &request)
        return try await send(request)
    }

    public func updateTask(id: UUID, title: String, notes: String?) async throws -> PCCTask {
        var request = makeRequest(path: "v1/tasks/\(id)", method: "PUT")
        try attach(SaveTaskPayload(title: title, notes: notes), to: &request)
        return try await send(request)
    }

    public func deleteTask(id: UUID) async throws {
        let request = makeRequest(path: "v1/tasks/\(id)", method: "DELETE")
        let (_, response) = try await session.data(for: request)
        try Self.checkStatus(response)
    }

    public func setTaskCompletion(id: UUID, isComplete: Bool) async throws -> PCCTask {
        let path = "v1/tasks/\(id)/\(isComplete ? "complete" : "incomplete")"
        let request = makeRequest(path: path, method: "PUT")
        return try await send(request)
    }

    public func assignTaskProject(id: UUID, projectID: UUID?) async throws -> PCCTask {
        var request = makeRequest(path: "v1/tasks/\(id)/project", method: "PUT")
        try attach(AssignTaskProjectPayload(projectID: projectID), to: &request)
        return try await send(request)
    }

    public func setTaskDeadline(id: UUID, dueDate: Date?) async throws -> PCCTask {
        var request = makeRequest(path: "v1/tasks/\(id)/deadline", method: "PUT")
        try attach(SetTaskDeadlinePayload(dueDate: dueDate), to: &request)
        return try await send(request)
    }

    public func assignTaskCourse(id: UUID, courseID: UUID?) async throws -> PCCTask {
        var request = makeRequest(path: "v1/tasks/\(id)/course", method: "PUT")
        try attach(AssignTaskCoursePayload(courseID: courseID), to: &request)
        return try await send(request)
    }

    private struct SaveTaskPayload: Encodable {
        let title: String
        let notes: String?
    }

    private struct AssignTaskProjectPayload: Encodable {
        let projectID: UUID?
    }

    private struct SetTaskDeadlinePayload: Encodable {
        let dueDate: Date?
    }

    private struct AssignTaskCoursePayload: Encodable {
        let courseID: UUID?
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
        guard let http = response as? HTTPURLResponse else {
            throw TasksAPIClientError.unexpectedResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw TasksAPIClientError.serverError(status: http.statusCode)
        }
    }
}
