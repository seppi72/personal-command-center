import Fluent
import Vapor

struct CourseResponse: Content {
    let id: UUID
    let name: String
    let termMonth: Int
    let termYear: Int
    let dueDate: Date?

    init(_ course: Course) throws {
        self.id = try course.requireID()
        self.name = course.name
        self.termMonth = course.termMonth
        self.termYear = course.termYear
        self.dueDate = course.dueDate
    }
}

/// Create and edit share this shape — a Course's name and Term are always
/// set together, unlike its Deadline (its own endpoint, below).
struct SaveCourseRequest: Content {
    let name: String
    let termMonth: Int
    let termYear: Int
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
        try await Course.query(on: req.db).all().map(CourseResponse.init)
    }

    func create(req: Request) async throws -> CourseResponse {
        let payload = try req.content.decode(SaveCourseRequest.self)
        let course = Course(
            name: try Self.validatedName(payload.name),
            termMonth: try Self.validatedTermMonth(payload.termMonth),
            termYear: try Self.validatedTermYear(payload.termYear)
        )
        try await course.save(on: req.db)
        return try CourseResponse(course)
    }

    func update(req: Request) async throws -> CourseResponse {
        guard let course = try await findCourse(req: req) else {
            throw Abort(.notFound)
        }
        let payload = try req.content.decode(SaveCourseRequest.self)
        course.name = try Self.validatedName(payload.name)
        course.termMonth = try Self.validatedTermMonth(payload.termMonth)
        course.termYear = try Self.validatedTermYear(payload.termYear)
        try await course.save(on: req.db)
        return try CourseResponse(course)
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

    /// A Term's month is a calendar month, 1 (January) through 12 (December)
    /// — reject anything outside that range rather than persisting a Course
    /// with a nonsensical Term.
    private static func validatedTermMonth(_ termMonth: Int) throws -> Int {
        guard (1...12).contains(termMonth) else {
            throw Abort(.badRequest, reason: "termMonth must be between 1 and 12")
        }
        return termMonth
    }

    /// A Term's year is a real calendar year — reject a non-positive one
    /// rather than persisting a Course with a nonsensical Term.
    private static func validatedTermYear(_ termYear: Int) throws -> Int {
        guard termYear > 0 else {
            throw Abort(.badRequest, reason: "termYear must be a positive integer")
        }
        return termYear
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
        return try await Course.find(id, on: req.db)
    }
}
