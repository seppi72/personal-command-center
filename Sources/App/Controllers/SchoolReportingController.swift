import Fluent
import Vapor

/// The School screen's two academic figures, computed fresh on every request
/// and never stored — the same "derive, don't duplicate" shape Net Worth and
/// Work Hours already have (`CONTEXT.md`), so neither can drift from the
/// grades underneath it.
struct SchoolSummaryResponse: Content {
    /// The Term `termGWA` was computed over — echoed back so a client can
    /// tell which semester the figure describes, and `nil` when no `termID`
    /// was asked for.
    let termID: UUID?
    /// That Term's own General Weighted Average, or `nil` when no Course in
    /// it carries a counting mark yet.
    let termGWA: Double?
    /// Unit-weighted across every subject in every Term — *not* an average
    /// of the per-Term figures (`CONTEXT.md`). `nil` when nothing counts
    /// yet.
    let cumulativeGWA: Double?
    /// Always cumulative: units over every passed subject, all Terms.
    let unitsEarned: Double
}

/// Issue #92: read-only, computed rollups over Course grades and units —
/// School's counterpart to `FinancesReportingController`.
///
/// One endpoint rather than that controller's five, because these figures
/// don't just share a response shape, they share a *tile row*: the GWA tile
/// shows the Term figure with the cumulative one beneath it, and Units
/// Earned sits beside them. Splitting them would make the screen issue three
/// requests for one row that must agree with itself.
struct SchoolReportingController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get("school-summary", use: summary)
    }

    /// Both figures over every Course, plus the per-Term GWA when `termID`
    /// names a Term.
    ///
    /// Loads every Course once and filters in memory rather than issuing a
    /// second scoped query: the cumulative figures need every row anyway,
    /// and one load can't disagree with itself the way two queries could
    /// (`FinancesReportingController.currentNetWorth`'s own reasoning).
    ///
    /// An unknown `termID` is a bad request, not a silent `nil` figure — a
    /// null GWA already means "no marks yet", and letting a typo produce the
    /// same answer would hide it.
    func summary(req: Request) async throws -> SchoolSummaryResponse {
        let termID = try await Self.validatedTermID(req)
        let courses = try await Course.query(on: req.db).all()

        func contributions(in courses: [Course]) -> [SchoolFigures.Contribution] {
            courses.map { SchoolFigures.Contribution(grade: $0.grade, units: $0.units) }
        }

        let termContributions = termID.map { id in
            contributions(in: courses.filter { $0.$term.id == id })
        }
        return SchoolSummaryResponse(
            termID: termID,
            termGWA: termContributions.flatMap(SchoolFigures.generalWeightedAverage(over:)),
            cumulativeGWA: SchoolFigures.generalWeightedAverage(over: contributions(in: courses)),
            unitsEarned: SchoolFigures.unitsEarned(over: contributions(in: courses))
        )
    }

    private static func validatedTermID(_ req: Request) async throws -> UUID? {
        guard let raw = req.query[String.self, at: "termID"] else { return nil }
        guard let id = UUID(uuidString: raw) else {
            throw Abort(.badRequest, reason: "termID must be a UUID")
        }
        guard try await Term.find(id, on: req.db) != nil else {
            throw Abort(.badRequest, reason: "no Term with that id")
        }
        return id
    }
}
