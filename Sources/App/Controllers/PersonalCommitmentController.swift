import Fluent
import Vapor

struct PersonalCommitmentResponse: Content {
    let id: UUID
    let title: String
    let startDate: Date
    let endDate: Date
    let recurrenceRule: String?
    let syncStatus: String
    let courseID: UUID?

    init(_ commitment: PersonalCommitment) throws {
        self.id = try commitment.requireID()
        self.title = commitment.title
        self.startDate = commitment.startDate
        self.endDate = commitment.endDate
        self.recurrenceRule = commitment.recurrenceRule
        self.syncStatus = commitment.syncStatus.rawValue
        self.courseID = commitment.$course.id
    }
}

/// `courseID: nil` (or the key omitted entirely) means this Commitment isn't
/// a class meeting for any Course — ticket #56's single optional link,
/// folded into the same full-replace request create/update already share
/// rather than a separate `PUT .../course` endpoint like Task/Course use:
/// unlike Task's Project/Course link (ADR-0003), this one has no
/// mutual-exclusivity logic to enforce.
struct SavePersonalCommitmentRequest: Content {
    let title: String
    let startDate: Date
    let endDate: Date
    let recurrenceRule: String?
    let courseID: UUID?
}

struct PersonalCommitmentController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let commitments = routes.grouped("personal-commitments")
        commitments.get(use: index)
        commitments.post(use: create)
        commitments.group(":commitmentID") { commitment in
            commitment.put(use: update)
            commitment.delete(use: delete)
        }
    }

    /// Lists every Commitment, or Commitments scoped to one Course when
    /// `?courseID=` is given — mirrors the same `?courseID=` filter Task and
    /// Time Entry's own `index` already support (ticket #56).
    func index(req: Request) async throws -> [PersonalCommitmentResponse] {
        var query = PersonalCommitment.query(on: req.db)
        if let courseID = req.query[UUID.self, at: "courseID"] {
            query = query.filter(\.$course.$id == courseID)
        }
        return try await query.all().map(PersonalCommitmentResponse.init)
    }

    /// Saves the Commitment first (so it has an id and a stable
    /// `externalEventID` to push under), then pushes it to CalDAV — the
    /// local, canonical write always happens; the push is logged
    /// separately (`CalendarSyncService.push`) and never blocks or fails
    /// this response.
    func create(req: Request) async throws -> PersonalCommitmentResponse {
        let payload = try req.content.decode(SavePersonalCommitmentRequest.self)
        let courseID = try await validatedCourseID(payload.courseID, req: req)
        let commitment = PersonalCommitment(
            title: try Self.validatedTitle(payload.title),
            startDate: payload.startDate,
            endDate: try Self.validatedEndDate(payload.endDate, after: payload.startDate),
            recurrenceRule: Self.normalizedRecurrenceRule(payload.recurrenceRule),
            courseID: courseID
        )
        try await commitment.save(on: req.db)
        await syncService(req).push(commitment, action: "personal_commitment.create")
        return try PersonalCommitmentResponse(commitment)
    }

    func update(req: Request) async throws -> PersonalCommitmentResponse {
        guard let commitment = try await findCommitment(req: req) else {
            throw Abort(.notFound)
        }
        let payload = try req.content.decode(SavePersonalCommitmentRequest.self)
        let courseID = try await validatedCourseID(payload.courseID, req: req)
        commitment.title = try Self.validatedTitle(payload.title)
        commitment.startDate = payload.startDate
        commitment.endDate = try Self.validatedEndDate(payload.endDate, after: payload.startDate)
        commitment.recurrenceRule = Self.normalizedRecurrenceRule(payload.recurrenceRule)
        commitment.$course.id = courseID
        try await commitment.save(on: req.db)
        await syncService(req).push(commitment, action: "personal_commitment.update")
        return try PersonalCommitmentResponse(commitment)
    }

    /// Removes the CalDAV event first, while the Commitment's id is still
    /// available for the resulting `AutomationLog` entry, then deletes the
    /// local row regardless of whether that removal succeeded — same
    /// "canonical write always happens, CalDAV outcome is only logged"
    /// shape as `create`/`update`.
    func delete(req: Request) async throws -> HTTPStatus {
        guard let commitment = try await findCommitment(req: req) else {
            throw Abort(.notFound)
        }
        await syncService(req).remove(commitment, action: "personal_commitment.delete")
        try await commitment.delete(on: req.db)
        return .noContent
    }

    private func syncService(_ req: Request) -> CalendarSyncService {
        CalendarSyncService(calDAVClient: req.application.calDAVClient, db: req.db, logger: req.logger)
    }

    /// A Commitment is created/edited "with a title" — reject an empty or
    /// whitespace-only one, mirroring `TaskController`/`ProjectController`.
    private static func validatedTitle(_ title: String) throws -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw Abort(.badRequest, reason: "title must not be empty")
        }
        return trimmed
    }

    /// An end time at or before its start time isn't a meaningful
    /// "start/end time" (spec #1, user story 17) — reject it rather than
    /// persisting a zero-or-negative-length Commitment.
    private static func validatedEndDate(_ endDate: Date, after startDate: Date) throws -> Date {
        guard endDate > startDate else {
            throw Abort(.badRequest, reason: "endDate must be after startDate")
        }
        return endDate
    }

    /// A non-nil `courseID` must resolve to a real Course — same check and
    /// error shape as `TaskController.assignCourse` for the identical case
    /// (spec #56, user story 5). `nil` passes straight through: an
    /// unattached Commitment is a valid, ordinary state, not an error.
    private func validatedCourseID(_ courseID: UUID?, req: Request) async throws -> UUID? {
        guard let courseID else { return nil }
        guard try await Course.find(courseID, on: req.db) != nil else {
            throw Abort(.badRequest, reason: "no such Course")
        }
        return courseID
    }

    /// Recurrence is optional: missing, empty, and whitespace-only all
    /// collapse to "no recurrence" rather than persisting a blank rule,
    /// mirroring `TaskController.normalizedNotes`.
    private static func normalizedRecurrenceRule(_ recurrenceRule: String?) -> String? {
        guard let trimmed = recurrenceRule?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func findCommitment(req: Request) async throws -> PersonalCommitment? {
        guard let id = req.parameters.get("commitmentID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        return try await PersonalCommitment.find(id, on: req.db)
    }
}
