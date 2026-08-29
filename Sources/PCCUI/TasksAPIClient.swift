import Foundation

/// Talks to the backend's `/v1/tasks` REST endpoints (see
/// `Sources/App/Controllers/TaskController.swift`). A protocol so a
/// different implementation could stand in during previews/manual testing
/// without a running backend — no such fake exists in this package yet, but
/// the seam is here for one.
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
/// Transport (request construction, encoding/decoding, status validation) is
/// `PCCHTTPTransport`'s; this struct owns only its own endpoints and payload
/// shapes.
public struct URLSessionTasksAPIClient: TasksAPIClient {
    private let transport: PCCHTTPTransport

    public init(baseURL: URL, bearerToken: String, session: URLSession = .shared) {
        self.transport = PCCHTTPTransport(baseURL: baseURL, bearerToken: bearerToken, session: session)
    }

    public func listTasks(projectID: UUID?, courseID: UUID?) async throws -> [PCCTask] {
        let request = try makeRequest(
            path: "v1/tasks",
            method: "GET",
            query: ["projectID": projectID.map(PCCHTTPTransport.QueryValue.uuid),
                    "courseID": courseID.map(PCCHTTPTransport.QueryValue.uuid)]
        )
        return try await send(request)
    }

    public func createTask(title: String, notes: String?) async throws -> PCCTask {
        var request = try makeRequest(path: "v1/tasks", method: "POST")
        try attach(SaveTaskPayload(title: title, notes: notes), to: &request)
        return try await send(request)
    }

    public func updateTask(id: UUID, title: String, notes: String?) async throws -> PCCTask {
        var request = try makeRequest(path: "v1/tasks/\(id)", method: "PUT")
        try attach(SaveTaskPayload(title: title, notes: notes), to: &request)
        return try await send(request)
    }

    public func deleteTask(id: UUID) async throws {
        let request = try makeRequest(path: "v1/tasks/\(id)", method: "DELETE")
        try await sendNoBody(request)
    }

    public func setTaskCompletion(id: UUID, isComplete: Bool) async throws -> PCCTask {
        let path = "v1/tasks/\(id)/\(isComplete ? "complete" : "incomplete")"
        let request = try makeRequest(path: path, method: "PUT")
        return try await send(request)
    }

    public func assignTaskProject(id: UUID, projectID: UUID?) async throws -> PCCTask {
        var request = try makeRequest(path: "v1/tasks/\(id)/project", method: "PUT")
        try attach(AssignTaskProjectPayload(projectID: projectID), to: &request)
        return try await send(request)
    }

    public func setTaskDeadline(id: UUID, dueDate: Date?) async throws -> PCCTask {
        var request = try makeRequest(path: "v1/tasks/\(id)/deadline", method: "PUT")
        try attach(SetTaskDeadlinePayload(dueDate: dueDate), to: &request)
        return try await send(request)
    }

    public func assignTaskCourse(id: UUID, courseID: UUID?) async throws -> PCCTask {
        var request = try makeRequest(path: "v1/tasks/\(id)/course", method: "PUT")
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
            unexpectedResponse: TasksAPIClientError.unexpectedResponse,
            serverError: TasksAPIClientError.serverError
        )
    }

    private func sendNoBody(_ request: URLRequest) async throws {
        try await transport.sendExpectingNoBody(
            request,
            unexpectedResponse: TasksAPIClientError.unexpectedResponse,
            serverError: TasksAPIClientError.serverError
        )
    }
}
