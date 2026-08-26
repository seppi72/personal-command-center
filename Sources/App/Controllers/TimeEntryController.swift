import Fluent
import Vapor

struct TimeEntryResponse: Content {
    let id: UUID
    let startDate: Date
    let endDate: Date
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
/// assigned a container through its own follow-up endpoints.
struct SaveTimeEntryRequest: Content {
    let startDate: Date
    let endDate: Date
    let notes: String?
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
        let container = try Self.validatedContainer(payload)
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
        let container = try Self.validatedContainer(payload)
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

    /// Exactly one of `taskID`/`projectID`/`clientID`/`courseID` is required
    /// (ADR-0004) — reject zero or more than one rather than picking a
    /// priority order among them.
    private static func validatedContainer(_ payload: SaveTimeEntryRequest) throws -> TimeEntryContainer {
        let given = [payload.taskID, payload.projectID, payload.clientID, payload.courseID].compactMap { $0 }
        guard given.count == 1 else {
            throw Abort(
                .badRequest,
                reason: "exactly one of taskID/projectID/clientID/courseID is required"
            )
        }
        if let taskID = payload.taskID { return .task(taskID) }
        if let projectID = payload.projectID { return .project(projectID) }
        if let clientID = payload.clientID { return .client(clientID) }
        return .course(payload.courseID!)
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
    /// own overlap check.
    private func verifyNoOverlap(
        startDate: Date,
        endDate: Date,
        excluding excludedID: UUID?,
        req: Request
    ) async throws {
        var query = TimeEntry.query(on: req.db)
            .filter(\.$startDate < endDate)
            .filter(\.$endDate > startDate)
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
