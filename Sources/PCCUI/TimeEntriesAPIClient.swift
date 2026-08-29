import Foundation

/// Talks to the backend's `/v1/time-entries` REST endpoints (see
/// `Sources/App/Controllers/TimeEntryController.swift`). A protocol so a
/// different implementation could stand in during previews/manual testing
/// without a running backend — no such fake exists in this package yet, but
/// the seam is here for one.
public protocol TimeEntriesAPIClient: Sendable {
    /// Lists every Time Entry, or Time Entries scoped to one Task, Project,
    /// Client, and/or Course when the corresponding id is given.
    func listTimeEntries(taskID: UUID?, projectID: UUID?, clientID: UUID?, courseID: UUID?) async throws -> [TimeEntry]
    func createTimeEntry(_ values: TimeEntryFormValues) async throws -> TimeEntry
    func updateTimeEntry(id: UUID, values: TimeEntryFormValues) async throws -> TimeEntry
    func deleteTimeEntry(id: UUID) async throws

    // Ticket #28: the live timer's own sub-resource — see
    // `Sources/App/Controllers/TimeEntryController.swift`'s `getTimer`/
    // `startTimer`/`stopTimer`/`cancelTimer`.

    /// The currently running timer, or `nil` if none.
    func getActiveTimer() async throws -> TimeEntry?
    /// Starts a timer against `container`; fails if one is already running.
    func startTimer(container: TimeEntryContainer) async throws -> TimeEntry
    /// Stops the running timer into a completed Time Entry.
    func stopTimer() async throws -> TimeEntry
    /// Cancels the running timer, discarding it with no saved record.
    func cancelTimer() async throws
}

public enum TimeEntriesAPIClientError: Error {
    case unexpectedResponse
    case serverError(status: Int)
}

/// The real client: same bearer-token auth as every other route
/// (`BearerTokenAuthMiddleware`) — one token per device, issued out of band.
/// Transport (request construction, encoding/decoding, status validation) is
/// `PCCHTTPTransport`'s; this struct owns only its own endpoints and payload
/// shapes.
public struct URLSessionTimeEntriesAPIClient: TimeEntriesAPIClient {
    private let transport: PCCHTTPTransport

    public init(baseURL: URL, bearerToken: String, session: URLSession = .shared) {
        self.transport = PCCHTTPTransport(baseURL: baseURL, bearerToken: bearerToken, session: session)
    }

    public func listTimeEntries(
        taskID: UUID?, projectID: UUID?, clientID: UUID?, courseID: UUID?
    ) async throws -> [TimeEntry] {
        let request = try makeRequest(
            path: "v1/time-entries",
            method: "GET",
            query: ["taskID": taskID.map(PCCHTTPTransport.QueryValue.uuid),
                    "projectID": projectID.map(PCCHTTPTransport.QueryValue.uuid),
                    "clientID": clientID.map(PCCHTTPTransport.QueryValue.uuid),
                    "courseID": courseID.map(PCCHTTPTransport.QueryValue.uuid)]
        )
        return try await send(request)
    }

    public func createTimeEntry(_ values: TimeEntryFormValues) async throws -> TimeEntry {
        var request = try makeRequest(path: "v1/time-entries", method: "POST")
        try attach(SaveTimeEntryPayload(values), to: &request)
        return try await send(request)
    }

    public func updateTimeEntry(id: UUID, values: TimeEntryFormValues) async throws -> TimeEntry {
        var request = try makeRequest(path: "v1/time-entries/\(id)", method: "PUT")
        try attach(SaveTimeEntryPayload(values), to: &request)
        return try await send(request)
    }

    public func deleteTimeEntry(id: UUID) async throws {
        let request = try makeRequest(path: "v1/time-entries/\(id)", method: "DELETE")
        try await sendNoBody(request)
    }

    public func getActiveTimer() async throws -> TimeEntry? {
        let request = try makeRequest(path: "v1/time-entries/timer", method: "GET")
        // The backend returns a literal JSON `null` body when no timer is
        // running (`TimeEntryController.getTimer`) — `JSONDecoder` decodes
        // that straight into `nil` for an `Optional` top-level type, so this
        // is just `send` with `Response == TimeEntry?`.
        return try await send(request)
    }

    public func startTimer(container: TimeEntryContainer) async throws -> TimeEntry {
        var request = try makeRequest(path: "v1/time-entries/timer/start", method: "POST")
        try attach(StartTimerPayload(container), to: &request)
        return try await send(request)
    }

    public func stopTimer() async throws -> TimeEntry {
        try await send(makeRequest(path: "v1/time-entries/timer/stop", method: "PUT"))
    }

    public func cancelTimer() async throws {
        let request = try makeRequest(path: "v1/time-entries/timer/cancel", method: "PUT")
        try await sendNoBody(request)
    }

    private struct StartTimerPayload: Encodable {
        let taskID: UUID?
        let projectID: UUID?
        let clientID: UUID?
        let courseID: UUID?

        init(_ container: TimeEntryContainer) {
            switch container {
            case .task(let id):
                self.taskID = id
                self.projectID = nil
                self.clientID = nil
                self.courseID = nil
            case .project(let id):
                self.taskID = nil
                self.projectID = id
                self.clientID = nil
                self.courseID = nil
            case .client(let id):
                self.taskID = nil
                self.projectID = nil
                self.clientID = id
                self.courseID = nil
            case .course(let id):
                self.taskID = nil
                self.projectID = nil
                self.clientID = nil
                self.courseID = id
            }
        }
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
            unexpectedResponse: TimeEntriesAPIClientError.unexpectedResponse,
            serverError: TimeEntriesAPIClientError.serverError
        )
    }

    private func sendNoBody(_ request: URLRequest) async throws {
        try await transport.sendExpectingNoBody(
            request,
            unexpectedResponse: TimeEntriesAPIClientError.unexpectedResponse,
            serverError: TimeEntriesAPIClientError.serverError
        )
    }
}
