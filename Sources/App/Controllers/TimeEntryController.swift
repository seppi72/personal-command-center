import Fluent
import Vapor

struct TimeEntryResponse: Content {
    let id: UUID
    let startDate: Date
    /// `nil` while this Time Entry is a running live timer (ticket #28) —
    /// see `TimeEntry.isRunning`.
    let endDate: Date?
    let notes: String?
    let taskID: UUID?
    let projectID: UUID?
    let clientID: UUID?
    let courseID: UUID?

    init(_ timeEntry: TimeEntry) throws {
        self.id = try timeEntry.requireID()
        self.startDate = timeEntry.startDate
        self.endDate = timeEntry.endDate
        self.notes = timeEntry.notes
        self.taskID = timeEntry.$task.id
        self.projectID = timeEntry.$project.id
        self.clientID = timeEntry.$client.id
        self.courseID = timeEntry.$course.id
    }
}

/// The same shape serves both create and edit — exactly one of
/// `taskID`/`projectID`/`clientID`/`courseID` is required either way
/// (ADR-0004), unlike `PCCTask`, which is created container-less and only
/// assigned a container through its own follow-up endpoints. Manual entry
/// always specifies a concrete `endDate` — unlike a timer's `start`, there's
/// no "manually create a running Time Entry" story.
struct SaveTimeEntryRequest: Content {
    let startDate: Date
    let endDate: Date
    let notes: String?
    let taskID: UUID?
    let projectID: UUID?
    let clientID: UUID?
    let courseID: UUID?
}

/// Ticket #28: which Task/Project/Client/Course to start the timer against —
/// exactly one of these four is required, the same container shape as
/// `SaveTimeEntryRequest`, just without the times/notes a timer's `start`
/// doesn't take (its `startDate` is `now`; it has no `endDate` yet; notes
/// aren't part of this ticket's scope).
struct StartTimerRequest: Content {
    let taskID: UUID?
    let projectID: UUID?
    let clientID: UUID?
    let courseID: UUID?
}

struct TimeEntryController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let timeEntries = routes.grouped("time-entries")
        timeEntries.get(use: index)
        timeEntries.post(use: create)
        timeEntries.group(":timeEntryID") { timeEntry in
            timeEntry.put(use: update)
            timeEntry.delete(use: delete)
        }
        // Ticket #28: the live timer's own sub-resource — "timer" is a
        // literal path segment registered alongside ":timeEntryID", not a
        // conflicting parameter match; Vapor's router tries literal
        // segments before parameter ones at the same level.
        timeEntries.group("timer") { timer in
            timer.get(use: getTimer)
            timer.post("start", use: startTimer)
            timer.put("stop", use: stopTimer)
            timer.put("cancel", use: cancelTimer)
        }
    }

    /// Lists every Time Entry, or Time Entries scoped to one Task, Project,
    /// Client, and/or Course when `?taskID=`/`?projectID=`/`?clientID=`/
    /// `?courseID=` are given — combinable filters, mirroring
    /// `TaskController.index`. Since a Time Entry attaches to exactly one
    /// container (ADR-0004), combining filters across different containers
    /// simply yields an empty result rather than needing a special case.
    func index(req: Request) async throws -> [TimeEntryResponse] {
        var query = TimeEntry.query(on: req.db)
        if let taskID = req.query[UUID.self, at: "taskID"] {
            query = query.filter(\.$task.$id == taskID)
        }
        if let projectID = req.query[UUID.self, at: "projectID"] {
            query = query.filter(\.$project.$id == projectID)
        }
        if let clientID = req.query[UUID.self, at: "clientID"] {
            query = query.filter(\.$client.$id == clientID)
        }
        if let courseID = req.query[UUID.self, at: "courseID"] {
            query = query.filter(\.$course.$id == courseID)
        }
        return try await query.all().map(TimeEntryResponse.init)
    }

    func create(req: Request) async throws -> TimeEntryResponse {
        let payload = try req.content.decode(SaveTimeEntryRequest.self)
        let container = try Self.validatedContainer(
            taskID: payload.taskID, projectID: payload.projectID, clientID: payload.clientID, courseID: payload.courseID
        )
        try await verifyContainerExists(container, req: req)
        let endDate = try Self.validatedEndDate(payload.endDate, after: payload.startDate)
        try await verifyNoOverlap(startDate: payload.startDate, endDate: endDate, excluding: nil, req: req)
        let timeEntry = TimeEntry(
            startDate: payload.startDate,
            endDate: endDate,
            notes: Self.normalizedNotes(payload.notes),
            container: container
        )
        try await timeEntry.save(on: req.db)
        return try TimeEntryResponse(timeEntry)
    }

    /// Edits every field under the same validation as `create` (ticket #27's
    /// AC) — times, notes, and container all travel in the same
    /// `SaveTimeEntryRequest` this Time Entry is simply overwritten with,
    /// rather than separate per-field endpoints like `TaskController`'s.
    func update(req: Request) async throws -> TimeEntryResponse {
        guard let timeEntry = try await findTimeEntry(req: req) else {
            throw Abort(.notFound)
        }
        let payload = try req.content.decode(SaveTimeEntryRequest.self)
        let container = try Self.validatedContainer(
            taskID: payload.taskID, projectID: payload.projectID, clientID: payload.clientID, courseID: payload.courseID
        )
        try await verifyContainerExists(container, req: req)
        let endDate = try Self.validatedEndDate(payload.endDate, after: payload.startDate)
        try await verifyNoOverlap(
            startDate: payload.startDate,
            endDate: endDate,
            excluding: try timeEntry.requireID(),
            req: req
        )
        timeEntry.startDate = payload.startDate
        timeEntry.endDate = endDate
        timeEntry.notes = Self.normalizedNotes(payload.notes)
        timeEntry.setContainer(container)
        try await timeEntry.save(on: req.db)
        return try TimeEntryResponse(timeEntry)
    }

    func delete(req: Request) async throws -> HTTPStatus {
        guard let timeEntry = try await findTimeEntry(req: req) else {
            throw Abort(.notFound)
        }
        try await timeEntry.delete(on: req.db)
        return .noContent
    }

    /// Ticket #28: starts a live timer — a `TimeEntry` created with
    /// `startDate = now` and no `endDate` yet (`TimeEntry.isRunning`), under
    /// the same container-exclusivity/existence validation as `create`.
    /// Only one timer may run at a time, checked before the container is
    /// even decoded so a bad container on the second request can't leak
    /// past the "already running" rejection.
    func startTimer(req: Request) async throws -> TimeEntryResponse {
        guard try await activeTimer(req: req) == nil else {
            throw Abort(.badRequest, reason: "a timer is already running")
        }
        let payload = try req.content.decode(StartTimerRequest.self)
        let container = try Self.validatedContainer(
            taskID: payload.taskID, projectID: payload.projectID, clientID: payload.clientID, courseID: payload.courseID
        )
        try await verifyContainerExists(container, req: req)
        let timer = TimeEntry(startDate: Date(), container: container)
        try await timer.save(on: req.db)
        return try TimeEntryResponse(timer)
    }

    /// Ticket #28: the currently running timer, or a literal JSON `null` if
    /// none — queried fresh from the database on every call, so it reflects
    /// a timer started by a separate, unrelated request rather than being
    /// per-connection state. `TimeEntryResponse?` can't be returned
    /// directly from a route handler (Vapor has no `AsyncResponseEncodable`
    /// conformance for `Optional`), so the response is built by hand.
    func getTimer(req: Request) async throws -> Response {
        guard let timer = try await activeTimer(req: req) else {
            let response = Response(status: .ok)
            response.headers.contentType = .json
            response.body = .init(string: "null")
            return response
        }
        let response = Response(status: .ok)
        try response.content.encode(try TimeEntryResponse(timer))
        return response
    }

    /// Ticket #28: stops the running timer into a completed Time Entry —
    /// `endDate = now`, under the same zero-duration/overlap validation as
    /// `update`. A rejected span leaves the timer running, unchanged:
    /// nothing is mutated or saved until both checks pass.
    func stopTimer(req: Request) async throws -> TimeEntryResponse {
        guard let timer = try await activeTimer(req: req) else {
            throw Abort(.notFound)
        }
        let endDate = try Self.validatedEndDate(Date(), after: timer.startDate)
        try await verifyNoOverlap(
            startDate: timer.startDate, endDate: endDate, excluding: try timer.requireID(), req: req
        )
        timer.endDate = endDate
        try await timer.save(on: req.db)
        return try TimeEntryResponse(timer)
    }

    /// Ticket #28: cancels the running timer outright — deletes the row
    /// with no saved record, unlike `stopTimer`, which completes it.
    func cancelTimer(req: Request) async throws -> HTTPStatus {
        guard let timer = try await activeTimer(req: req) else {
            throw Abort(.notFound)
        }
        try await timer.delete(on: req.db)
        return .noContent
    }

    /// The one Time Entry with no `endDate`, if any (`TimeEntry.isRunning`)
    /// — at most one ever exists, enforced by `startTimer`.
    private func activeTimer(req: Request) async throws -> TimeEntry? {
        try await TimeEntry.query(on: req.db).filter(\.$endDate == nil).first()
    }

    /// Exactly one of `taskID`/`projectID`/`clientID`/`courseID` is required
    /// (ADR-0004) — reject zero or more than one rather than picking a
    /// priority order among them. Shared by `create`/`update`'s
    /// `SaveTimeEntryRequest` and `startTimer`'s `StartTimerRequest`, which
    /// carry the same four ids without a common payload type.
    private static func validatedContainer(
        taskID: UUID?, projectID: UUID?, clientID: UUID?, courseID: UUID?
    ) throws -> TimeEntryContainer {
        let given = [taskID, projectID, clientID, courseID].compactMap { $0 }
        guard given.count == 1 else {
            throw Abort(
                .badRequest,
                reason: "exactly one of taskID/projectID/clientID/courseID is required"
            )
        }
        if let taskID { return .task(taskID) }
        if let projectID { return .project(projectID) }
        if let clientID { return .client(clientID) }
        return .course(courseID!)
    }

    private func verifyContainerExists(_ container: TimeEntryContainer, req: Request) async throws {
        switch container {
        case .task(let id):
            guard try await PCCTask.find(id, on: req.db) != nil else {
                throw Abort(.badRequest, reason: "no such Task")
            }
        case .project(let id):
            guard try await Project.find(id, on: req.db) != nil else {
                throw Abort(.badRequest, reason: "no such Project")
            }
        case .client(let id):
            guard try await PCCClient.find(id, on: req.db) != nil else {
                throw Abort(.badRequest, reason: "no such Client")
            }
        case .course(let id):
            guard try await Course.find(id, on: req.db) != nil else {
                throw Abort(.badRequest, reason: "no such Course")
            }
        }
    }

    /// An end time at or before its start time isn't a meaningful span —
    /// reject it rather than persisting a zero-or-negative-length Time
    /// Entry, mirroring `PersonalCommitmentController.validatedEndDate`.
    private static func validatedEndDate(_ endDate: Date, after startDate: Date) throws -> Date {
        guard endDate > startDate else {
            throw Abort(.badRequest, reason: "endDate must be after startDate")
        }
        return endDate
    }

    /// Rejects a span that strictly overlaps an existing Time Entry's span —
    /// touching boundaries (one ends exactly when another starts) are
    /// allowed, so the comparison uses strict `<`/`>` rather than `<=`/`>=`.
    /// The check is global, not scoped to the same container: Work Hours
    /// tracks one person's time, who can only be doing one thing at once,
    /// regardless of which Task/Project/Client/Course each span is logged
    /// against. `excludedID` leaves the Time Entry being edited out of its
    /// own overlap check. A running timer (`endDate == nil`, ticket #28) has
    /// no end yet to compare against, so it's treated as open-ended —
    /// `endDate IS NULL OR endDate > startDate` — rather than being excluded
    /// by plain SQL `NULL > x` semantics: a manual entry (or another timer
    /// `start`) that begins before an already-running timer still overlaps
    /// it, the same "only doing one thing at once" invariant this check
    /// already enforces between two completed entries.
    private func verifyNoOverlap(
        startDate: Date,
        endDate: Date,
        excluding excludedID: UUID?,
        req: Request
    ) async throws {
        var query = TimeEntry.query(on: req.db)
            .filter(\.$startDate < endDate)
            .group(.or) { group in
                group.filter(\.$endDate == nil)
                group.filter(\.$endDate > startDate)
            }
        if let excludedID {
            query = query.filter(\.$id != excludedID)
        }
        guard try await query.first() == nil else {
            throw Abort(.badRequest, reason: "overlaps an existing Time Entry")
        }
    }

    /// Notes are optional: missing, empty, and whitespace-only all collapse
    /// to "no notes" rather than persisting a blank string, mirroring
    /// `TaskController.normalizedNotes`.
    private static func normalizedNotes(_ notes: String?) -> String? {
        guard let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func findTimeEntry(req: Request) async throws -> TimeEntry? {
        guard let id = req.parameters.get("timeEntryID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        return try await TimeEntry.find(id, on: req.db)
    }
}
