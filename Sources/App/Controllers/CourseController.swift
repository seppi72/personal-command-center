import Fluent
import Vapor

struct CourseResponse: Content {
    let id: UUID
    let name: String
    let termID: UUID
    /// The whole Term, not just its id — every screen that lists Courses
    /// also labels, badges or groups them by Term, and a nested Term saves
    /// each of those a second round trip plus a client-side join that could
    /// disagree with this response. Requires the caller to have eager-loaded
    /// `$term` (`Self.query(on:)`).
    let term: TermResponse
    let dueDate: Date?
    let units: Double
    /// The final mark, or `nil` while the subject is ongoing (issue #92).
    let grade: Grade?

    init(_ course: Course) throws {
        self.id = try course.requireID()
        self.name = course.name
        self.termID = course.$term.id
        self.term = try TermResponse(course.term)
        self.dueDate = course.dueDate
        self.units = course.units
        self.grade = course.grade
    }
}

/// Create and edit share this shape — a Course's name, Term, units and mark
/// are always set together on the one form, unlike its Deadline (its own
/// endpoint, below).
///
/// `grade` omitted (or null) means the subject is ongoing, and is also how a
/// mark is cleared — the same "missing means null" shape
/// `SetCourseDeadlineRequest` has. `units` has no such reading: it is
/// required on every save, since a unitless Course would silently corrupt
/// both GWA and Units Earned.
struct SaveCourseRequest: Content {
    let name: String
    let termID: UUID
    let units: Double
    let grade: Grade?

    init(name: String, termID: UUID, units: Double, grade: Grade? = nil) {
        self.name = name
        self.termID = termID
        self.units = units
        self.grade = grade
    }
}

/// `dueDate: nil` (or the key omitted entirely) clears the Course's
/// Deadline — same "missing means null" shape as `SetProjectDeadlineRequest`.
struct SetCourseDeadlineRequest: Content {
    let dueDate: Date?
}

struct CourseController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let courses = routes.grouped("courses")
        courses.get(use: index)
        courses.post(use: create)
        courses.group(":courseID") { course in
            course.put(use: update)
            course.delete(use: delete)
            course.put("deadline", use: setDeadline)
        }
    }

    /// Lists every Course — a Course is top-level, not nested under
    /// anything, unlike `ProjectController.index`'s optional `?clientID=`
    /// scoping.
    func index(req: Request) async throws -> [CourseResponse] {
        try await Self.query(on: req.db).all().map(CourseResponse.init)
    }

    func create(req: Request) async throws -> CourseResponse {
        let payload = try req.content.decode(SaveCourseRequest.self)
        let term = try await Self.requireTerm(id: payload.termID, req: req)
        let course = Course(
            name: try Self.validatedName(payload.name),
            termID: try term.requireID(),
            units: try Self.validatedUnits(payload.units),
            grade: payload.grade
        )
        try await course.save(on: req.db)
        course.$term.value = term
        return try CourseResponse(course)
    }

    func update(req: Request) async throws -> CourseResponse {
        guard let course = try await findCourse(req: req) else {
            throw Abort(.notFound)
        }
        let payload = try req.content.decode(SaveCourseRequest.self)
        let term = try await Self.requireTerm(id: payload.termID, req: req)
        course.name = try Self.validatedName(payload.name)
        course.$term.id = try term.requireID()
        course.units = try Self.validatedUnits(payload.units)
        course.grade = payload.grade
        try await course.save(on: req.db)
        course.$term.value = term
        return try CourseResponse(course)
    }

    /// Every Course read eager-loads its Term, since `CourseResponse` nests
    /// the whole Term rather than just its id — one query with a join beats
    /// a Term lookup per Course.
    private static func query(on db: any Database) -> QueryBuilder<Course> {
        Course.query(on: db).with(\.$term)
    }

    /// A Course belongs to exactly one Term, required — a `termID` naming no
    /// Term is a bad request, not a Course quietly saved without one
    /// (`docs/adr/0012-term-is-an-entity.md`).
    private static func requireTerm(id: UUID, req: Request) async throws -> Term {
        guard let term = try await Term.find(id, on: req.db) else {
            throw Abort(.badRequest, reason: "no Term with that id")
        }
        return term
    }

    /// A Course is created/edited "with a name" — reject an empty or
    /// whitespace-only one, mirroring `ProjectController`/`ClientController`.
    private static func validatedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw Abort(.badRequest, reason: "name must not be empty")
        }
        return trimmed
    }

    /// A Course weighs something, always (issue #92) — reject zero, a
    /// negative count, and a non-finite one. Zero is rejected rather than
    /// stored because a zero-unit subject contributes nothing to either
    /// figure while looking like real data, and a whole Term of them would
    /// leave GWA undefined with nothing on screen saying why.
    ///
    /// Decimal rather than integer so half-unit subjects stay expressible,
    /// so there's no whole-number check here.
    private static func validatedUnits(_ units: Double) throws -> Double {
        guard units.isFinite, units > 0 else {
            throw Abort(.badRequest, reason: "units must be a positive number")
        }
        return units
    }

    /// Deleting a Course doesn't delete its Tasks — `AddCourseToPCCTask`'s
    /// `.setNull` foreign key makes them Course-less instead (ticket #20),
    /// the same orphaning shape `SprintController.delete` already has for a
    /// deleted Sprint's Tasks. No manual query needed here; the FK handles it.
    func delete(req: Request) async throws -> HTTPStatus {
        guard let course = try await findCourse(req: req) else {
            throw Abort(.notFound)
        }
        let courseID = try course.requireID()
        try await Self.verifyNoReferencingTimeEntries(courseID: courseID, req: req)
        try await Self.verifyNoReferencingPersonalCommitments(courseID: courseID, req: req)
        try await Self.verifyNoReferencingProjects(courseID: courseID, req: req)
        try await course.delete(on: req.db)
        return .noContent
    }

    /// Ticket #29: a Course can't be deleted while any Time Entry still
    /// references it — mirrors `TaskController`'s identical check.
    private static func verifyNoReferencingTimeEntries(courseID: UUID, req: Request) async throws {
        guard try await TimeEntry.query(on: req.db).filter(\.$course.$id == courseID).first() == nil else {
            throw Abort(.badRequest, reason: "cannot delete a Course with Time Entries attached")
        }
    }

    /// Ticket #56: a Course can't be deleted while any Personal Commitment
    /// still references it either — same status and error shape as
    /// `verifyNoReferencingTimeEntries`, just naming the Commitment side.
    private static func verifyNoReferencingPersonalCommitments(courseID: UUID, req: Request) async throws {
        guard try await PersonalCommitment.query(on: req.db).filter(\.$course.$id == courseID).first() == nil else {
            throw Abort(.badRequest, reason: "cannot delete a Course with Personal Commitments attached")
        }
    }

    /// Ticket #88: a Course can't be deleted while a Project still belongs
    /// to it (ADR-0011) — the owner must reassign or delete those Projects
    /// first, rather than the delete orphaning a Project that only made
    /// sense as coursework. Same shape as the two guards above.
    private static func verifyNoReferencingProjects(courseID: UUID, req: Request) async throws {
        guard try await Project.query(on: req.db).filter(\.$course.$id == courseID).first() == nil else {
            throw Abort(.badRequest, reason: "cannot delete a Course with Projects attached")
        }
    }

    /// Attach, change, or remove (`dueDate: null`) a Course's Deadline —
    /// all three ACs are the same write, mirroring `ProjectController.setDeadline`.
    func setDeadline(req: Request) async throws -> CourseResponse {
        guard let course = try await findCourse(req: req) else {
            throw Abort(.notFound)
        }
        let payload = try req.content.decode(SetCourseDeadlineRequest.self)
        course.dueDate = payload.dueDate
        try await course.save(on: req.db)
        return try CourseResponse(course)
    }

    private func findCourse(req: Request) async throws -> Course? {
        guard let id = req.parameters.get("courseID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        return try await Self.query(on: req.db).filter(\.$id == id).first()
    }
}
