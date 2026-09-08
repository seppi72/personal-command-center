import Fluent
import Vapor

struct TermResponse: Content {
    let id: UUID
    let year: Int
    let semester: Semester
    /// Derived from `year` and `semester` (`Term.displayName`), never stored
    /// — a client renders this rather than composing its own spelling.
    let displayName: String
    let startDate: Date?
    let endDate: Date?

    init(_ term: Term) throws {
        self.id = try term.requireID()
        self.year = term.year
        self.semester = term.semester
        self.displayName = term.displayName
        self.startDate = term.startDate
        self.endDate = term.endDate
    }
}

/// Create and edit share this shape — a Term's identity (year plus semester)
/// and its calendar span are always set together, the same way a Course's
/// name and Term are.
///
/// `startDate`/`endDate` are optional but not independent: both, or neither.
/// A Term with only one end of its span can be neither overlap-checked
/// against another Term nor asked whether it contains today, so a half-set
/// range is rejected rather than stored.
struct SaveTermRequest: Content {
    let year: Int
    let semester: Semester
    let startDate: Date?
    let endDate: Date?
}

struct TermController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let terms = routes.grouped("terms")
        terms.get(use: index)
        terms.post(use: create)
        terms.group(":termID") { term in
            term.put(use: update)
            term.delete(use: delete)
        }
    }

    /// Lists every Term, earliest first — a Term is top-level, like a Course
    /// or a Client. Ordered here rather than by the client because the order
    /// is the domain's own (a school year runs 1st, 2nd, Summer), not a
    /// display preference.
    func index(req: Request) async throws -> [TermResponse] {
        let terms = try await Term.query(on: req.db).all()
        return try Self.inCalendarOrder(terms).map(TermResponse.init)
    }

    func create(req: Request) async throws -> TermResponse {
        let payload = try req.content.decode(SaveTermRequest.self)
        let year = try Self.validatedYear(payload.year)
        let span = try Self.validatedSpan(startDate: payload.startDate, endDate: payload.endDate)
        try await Self.verifyNotDuplicate(
            year: year, semester: payload.semester, excluding: nil, req: req)
        try await Self.verifyNoOverlap(span: span, excluding: nil, req: req)

        let term = Term(
            year: year, semester: payload.semester, startDate: span?.start, endDate: span?.end)
        try await term.save(on: req.db)
        return try TermResponse(term)
    }

    func update(req: Request) async throws -> TermResponse {
        guard let term = try await findTerm(req: req) else {
            throw Abort(.notFound)
        }
        let termID = try term.requireID()
        let payload = try req.content.decode(SaveTermRequest.self)
        let year = try Self.validatedYear(payload.year)
        let span = try Self.validatedSpan(startDate: payload.startDate, endDate: payload.endDate)
        try await Self.verifyNotDuplicate(
            year: year, semester: payload.semester, excluding: termID, req: req)
        try await Self.verifyNoOverlap(span: span, excluding: termID, req: req)

        term.year = year
        term.semester = payload.semester
        term.startDate = span?.start
        term.endDate = span?.end
        try await term.save(on: req.db)
        return try TermResponse(term)
    }

    /// A Term can't be deleted while any Course still belongs to it — the
    /// same referential guard `CourseController.delete` already applies for
    /// Time Entries, Personal Commitments and Projects, and Finances applies
    /// for an Account's Transactions. Cascading here would silently delete a
    /// semester of academic history.
    func delete(req: Request) async throws -> HTTPStatus {
        guard let term = try await findTerm(req: req) else {
            throw Abort(.notFound)
        }
        let termID = try term.requireID()
        guard try await Course.query(on: req.db).filter(\.$term.$id == termID).first() == nil else {
            throw Abort(.badRequest, reason: "cannot delete a Term with Courses attached")
        }
        try await term.delete(on: req.db)
        return .noContent
    }

    // MARK: - Validation

    /// A Term's year is a real calendar year — reject a non-positive one,
    /// mirroring the `termYear` check this replaced.
    private static func validatedYear(_ year: Int) throws -> Int {
        guard year > 0 else {
            throw Abort(.badRequest, reason: "year must be a positive integer")
        }
        return year
    }

    /// Both dates or neither, and the start no later than the end. Returns
    /// `nil` for the "not set yet" case so callers store two nulls rather
    /// than branching twice.
    private static func validatedSpan(startDate: Date?, endDate: Date?) throws
        -> (start: Date, end: Date)?
    {
        switch (startDate, endDate) {
        case (nil, nil):
            return nil
        case let (start?, end?):
            guard start <= end else {
                throw Abort(.badRequest, reason: "startDate must not be after endDate")
            }
            return (start, end)
        default:
            throw Abort(
                .badRequest, reason: "startDate and endDate must be set together or both omitted")
        }
    }

    /// Year plus semester is a Term's identity (`CONTEXT.md`), so a second
    /// row with the same pair is rejected with a readable reason rather than
    /// left to `CreateTerm`'s unique index, which would surface as an opaque
    /// database error.
    private static func verifyNotDuplicate(
        year: Int, semester: Semester, excluding termID: UUID?, req: Request
    ) async throws {
        var query = Term.query(on: req.db)
            .filter(\.$year == year)
            .filter(\.$semesterRawValue == semester.rawValue)
        if let termID {
            query = query.filter(\.$id != termID)
        }
        guard try await query.first() == nil else {
            throw Abort(
                .badRequest, reason: "a Term already exists for \(semester.displayName) \(year)")
        }
    }

    /// Two Terms whose date ranges overlap would give "which semester is
    /// happening now" two answers, and the School screen would show a
    /// different semester depending on sort order. Terms with no dates set
    /// can't overlap anything and are skipped.
    ///
    /// Ranges are treated as inclusive of both ends, matching how an
    /// academic calendar reads ("August 11 to December 20"), so a Term
    /// starting the same day another ends is an overlap.
    private static func verifyNoOverlap(
        span: (start: Date, end: Date)?, excluding termID: UUID?, req: Request
    ) async throws {
        guard let span else { return }
        var query = Term.query(on: req.db)
            .filter(\.$startDate <= span.end)
            .filter(\.$endDate >= span.start)
        if let termID {
            query = query.filter(\.$id != termID)
        }
        guard let clashing = try await query.first() else { return }
        throw Abort(
            .badRequest,
            reason: "date range overlaps \(clashing.displayName)")
    }

    // MARK: - Ordering

    /// Year first, then the order semesters run inside a year
    /// (`Semester.sortIndex`) — not the stored raw values, which sort
    /// alphabetically into "first, second, summer" only by coincidence.
    static func inCalendarOrder(_ terms: [Term]) -> [Term] {
        terms.sorted { ($0.year, $0.semester.sortIndex) < ($1.year, $1.semester.sortIndex) }
    }

    private func findTerm(req: Request) async throws -> Term? {
        guard let id = req.parameters.get("termID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        return try await Term.find(id, on: req.db)
    }
}
