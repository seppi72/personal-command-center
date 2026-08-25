import Foundation

/// Talks to the backend's `/v1/courses` REST endpoints (see
/// `Sources/App/Controllers/CourseController.swift`). A protocol so the view
/// model can be exercised against a fake in previews/manual testing without
/// a running backend.
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
public struct URLSessionCoursesAPIClient: CoursesAPIClient {
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

    public func listCourses() async throws -> [Course] {
        let request = makeRequest(path: "v1/courses", method: "GET")
        return try await send(request)
    }

    public func createCourse(name: String, termMonth: Int, termYear: Int) async throws -> Course {
        var request = makeRequest(path: "v1/courses", method: "POST")
        try attach(SaveCoursePayload(name: name, termMonth: termMonth, termYear: termYear), to: &request)
        return try await send(request)
    }

    public func updateCourse(id: UUID, name: String, termMonth: Int, termYear: Int) async throws -> Course {
        var request = makeRequest(path: "v1/courses/\(id)", method: "PUT")
        try attach(SaveCoursePayload(name: name, termMonth: termMonth, termYear: termYear), to: &request)
        return try await send(request)
    }

    public func deleteCourse(id: UUID) async throws {
        let request = makeRequest(path: "v1/courses/\(id)", method: "DELETE")
        let (_, response) = try await session.data(for: request)
        try HTTPResponseValidation.checkStatus(
            response,
            unexpectedResponse: CoursesAPIClientError.unexpectedResponse,
            serverError: CoursesAPIClientError.serverError
        )
    }

    public func setCourseDeadline(id: UUID, dueDate: Date?) async throws -> Course {
        var request = makeRequest(path: "v1/courses/\(id)/deadline", method: "PUT")
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

    private func attach<Body: Encodable>(_ body: Body, to request: inout URLRequest) throws {
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        try HTTPResponseValidation.checkStatus(
            response,
            unexpectedResponse: CoursesAPIClientError.unexpectedResponse,
            serverError: CoursesAPIClientError.serverError
        )
        return try decoder.decode(Response.self, from: data)
    }

    private func makeRequest(path: String, method: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        return request
    }
}
