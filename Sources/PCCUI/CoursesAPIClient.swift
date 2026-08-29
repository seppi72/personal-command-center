import Foundation

/// Talks to the backend's `/v1/courses` REST endpoints (see
/// `Sources/App/Controllers/CourseController.swift`). A protocol so a
/// different implementation could stand in during previews/manual testing
/// without a running backend — no such fake exists in this package yet, but
/// the seam is here for one.
public protocol CoursesAPIClient: Sendable {
    func listCourses() async throws -> [Course]
    func createCourse(name: String, termMonth: Int, termYear: Int) async throws -> Course
    func updateCourse(id: UUID, name: String, termMonth: Int, termYear: Int) async throws -> Course
    func deleteCourse(id: UUID) async throws
    /// Attaches, changes, or removes (`dueDate: nil`) a Course's Deadline.
    func setCourseDeadline(id: UUID, dueDate: Date?) async throws -> Course
}

public enum CoursesAPIClientError: Error {
    case unexpectedResponse
    case serverError(status: Int)
}

/// The real client: same bearer-token auth as every other route
/// (`BearerTokenAuthMiddleware`) — one token per device, issued out of band.
/// Transport (request construction, encoding/decoding, status validation) is
/// `PCCHTTPTransport`'s; this struct owns only its own endpoints and payload
/// shapes.
public struct URLSessionCoursesAPIClient: CoursesAPIClient {
    private let transport: PCCHTTPTransport

    public init(baseURL: URL, bearerToken: String, session: URLSession = .shared) {
        self.transport = PCCHTTPTransport(baseURL: baseURL, bearerToken: bearerToken, session: session)
    }

    public func listCourses() async throws -> [Course] {
        let request = try makeRequest(path: "v1/courses", method: "GET")
        return try await send(request)
    }

    public func createCourse(name: String, termMonth: Int, termYear: Int) async throws -> Course {
        var request = try makeRequest(path: "v1/courses", method: "POST")
        try attach(SaveCoursePayload(name: name, termMonth: termMonth, termYear: termYear), to: &request)
        return try await send(request)
    }

    public func updateCourse(id: UUID, name: String, termMonth: Int, termYear: Int) async throws -> Course {
        var request = try makeRequest(path: "v1/courses/\(id)", method: "PUT")
        try attach(SaveCoursePayload(name: name, termMonth: termMonth, termYear: termYear), to: &request)
        return try await send(request)
    }

    public func deleteCourse(id: UUID) async throws {
        let request = try makeRequest(path: "v1/courses/\(id)", method: "DELETE")
        try await sendNoBody(request)
    }

    public func setCourseDeadline(id: UUID, dueDate: Date?) async throws -> Course {
        var request = try makeRequest(path: "v1/courses/\(id)/deadline", method: "PUT")
        try attach(SetCourseDeadlinePayload(dueDate: dueDate), to: &request)
        return try await send(request)
    }

    private struct SaveCoursePayload: Encodable {
        let name: String
        let termMonth: Int
        let termYear: Int
    }

    private struct SetCourseDeadlinePayload: Encodable {
        let dueDate: Date?
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
            unexpectedResponse: CoursesAPIClientError.unexpectedResponse,
            serverError: CoursesAPIClientError.serverError
        )
    }

    private func sendNoBody(_ request: URLRequest) async throws {
        try await transport.sendExpectingNoBody(
            request,
            unexpectedResponse: CoursesAPIClientError.unexpectedResponse,
            serverError: CoursesAPIClientError.serverError
        )
    }
}
