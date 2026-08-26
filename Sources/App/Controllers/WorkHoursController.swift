import Fluent
import Vapor

/// One `groupBy=day` row: how many seconds were logged against `date`, the
/// local calendar day (`Calendar.current` — this process has no
/// owner-timezone concept of its own yet, so "local" means this server's
/// timezone) an entry's `startDate` falls on. Dense: one row per calendar
/// day in the query range, including a day with nothing logged
/// (`totalSeconds == 0`), per ticket #25's settled contract.
///
/// One `groupBy=project`/`client`/`task`/`course` row: `id`/`name` identify
/// the Project/Client/Task/Course, `totalSeconds` is its folded total
/// (`docs/adr/0005-work-hours-rollup-transitive-fold.md`). Sparse: a
/// container with a zero total in range is left out entirely, unlike a
/// `day` row.
///
/// One enum rather than one struct because the JSON key names genuinely
/// differ by case (`projectID`/`projectName` vs `clientID`/`clientName`,
/// etc.) — the settled API contract, so `date`/`totalSeconds` for `day` but
/// `{kind}ID`/`{kind}Name`/`totalSeconds` for the other four. `Codable`'s
/// synthesized conformance can't express that for one shape, so this
/// encodes by hand.
enum WorkHoursRow {
    case day(date: Date, totalSeconds: TimeInterval)
    case project(id: UUID, name: String, totalSeconds: TimeInterval)
    case client(id: UUID, name: String, totalSeconds: TimeInterval)
    case task(id: UUID, name: String, totalSeconds: TimeInterval)
    case course(id: UUID, name: String, totalSeconds: TimeInterval)
}

extension WorkHoursRow: Encodable {
    private enum CodingKeys: String, CodingKey {
        case date, totalSeconds
        case projectID, projectName
        case clientID, clientName
        case taskID, taskName
        case courseID, courseName
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .day(let date, let totalSeconds):
            try container.encode(date, forKey: .date)
            try container.encode(totalSeconds, forKey: .totalSeconds)
        case .project(let id, let name, let totalSeconds):
            try container.encode(id, forKey: .projectID)
            try container.encode(name, forKey: .projectName)
            try container.encode(totalSeconds, forKey: .totalSeconds)
        case .client(let id, let name, let totalSeconds):
            try container.encode(id, forKey: .clientID)
            try container.encode(name, forKey: .clientName)
            try container.encode(totalSeconds, forKey: .totalSeconds)
        case .task(let id, let name, let totalSeconds):
            try container.encode(id, forKey: .taskID)
            try container.encode(name, forKey: .taskName)
            try container.encode(totalSeconds, forKey: .totalSeconds)
        case .course(let id, let name, let totalSeconds):
            try container.encode(id, forKey: .courseID)
            try container.encode(name, forKey: .courseName)
            try container.encode(totalSeconds, forKey: .totalSeconds)
        }
    }
}

/// The five dimensions Work Hours can be rolled up by (`CONTEXT.md`) — a
/// day, or one of Time Entry's four containers. Sprint is deliberately not
/// a sixth case: a Sprint's entries already fold into their Project via the
/// owning Task's `project_id` (ADR-0005), so a Sprint dimension would just
/// duplicate part of the Project rollup.
enum WorkHoursGroupBy: String {
    case day, project, client, task, course
}

/// The four dimensions `WorkHoursController.containerRows` actually
/// handles — `WorkHoursGroupBy` minus `.day`, which `index` peels off
/// before ever reaching there. A second type rather than re-switching on
/// `WorkHoursGroupBy` inside `containerRows` and covering an unreachable
/// `.day` case a second time.
private enum ContainerGroupBy {
    case project, client, task, course

    init(_ groupBy: WorkHoursGroupBy) {
        switch groupBy {
        case .day: preconditionFailure("day is handled by dayRows, not containerRows")
        case .project: self = .project
        case .client: self = .client
        case .task: self = .task
        case .course: self = .course
        }
    }
}

/// A container's id/name paired with its folded total — what
/// `WorkHoursController.namedTotals` builds per Task/Project/Client/Course
/// and `sparseRows` turns into a `WorkHoursRow`. Named rather than left as
/// an anonymous tuple, since the same three fields travel together
/// everywhere in this file.
private struct NamedTotal {
    let id: UUID
    let name: String
    let totalSeconds: TimeInterval
}

/// Ticket #25: `GET /v1/work-hours` — the Work Hours rollup (`CONTEXT.md`),
/// one read-only endpoint serving all five `groupBy` values rather than
/// five separate routes, since they share the same query/validation shape
/// and differ only in how the same underlying Time Entries get bucketed.
struct WorkHoursController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.grouped("work-hours").get(use: index)
    }

    /// The response's row shape depends on `groupBy` (`WorkHoursRow`), so
    /// there's no single `Content` struct to declare as the return type —
    /// the response is built and encoded by hand, the same move
    /// `TimeEntryController.getTimer` already makes for its own
    /// not-one-fixed-shape response.
    func index(req: Request) async throws -> Response {
        let groupBy = try Self.validatedGroupBy(req)
        let (start, end) = try Self.validatedRange(req)
        let entries = try await completedEntries(start: start, end: end, req: req)
        let rows: [WorkHoursRow]
        if groupBy == .day {
            rows = Self.dayRows(entries: entries, start: start, end: end)
        } else {
            rows = try await containerRows(groupBy: ContainerGroupBy(groupBy), entries: entries, req: req)
        }
        let response = Response(status: .ok)
        try response.content.encode(rows, as: .json)
        return response
    }

    private static func validatedGroupBy(_ req: Request) throws -> WorkHoursGroupBy {
        guard
            let raw = req.query[String.self, at: "groupBy"],
            let groupBy = WorkHoursGroupBy(rawValue: raw)
        else {
            throw Abort(.badRequest, reason: "groupBy must be one of day, project, client, task, course")
        }
        return groupBy
    }

    /// `start`/`end` travel as plain ISO 8601 query-string values, parsed by
    /// hand — Vapor's query decoder defaults `Date` to
    /// `secondsSince1970` (unlike its JSON body decoder, which this API's
    /// `SaveTimeEntryRequest` etc. rely on defaulting to ISO 8601), so
    /// decoding straight into `Date` here would silently expect a different
    /// wire format than every other date in this API. `[start, end)`, both
    /// required (ticket #25) — missing, unparseable, or inverted all reject
    /// with the same `Abort(.badRequest, reason:)` shape
    /// `TimeEntryController.validatedEndDate` already uses.
    private static func validatedRange(_ req: Request) throws -> (start: Date, end: Date) {
        let formatter = ISO8601DateFormatter()
        guard
            let startRaw = req.query[String.self, at: "start"],
            let start = formatter.date(from: startRaw)
        else {
            throw Abort(.badRequest, reason: "start is required and must be an ISO 8601 date")
        }
        guard
            let endRaw = req.query[String.self, at: "end"],
            let end = formatter.date(from: endRaw)
        else {
            throw Abort(.badRequest, reason: "end is required and must be an ISO 8601 date")
        }
        guard end > start else {
            throw Abort(.badRequest, reason: "end must be after start")
        }
        return (start, end)
    }

    /// Every completed (`endDate != nil`) Time Entry starting in
    /// `[start, end)` — a running live timer contributes to no Work Hours
    /// total until it's stopped (`CONTEXT.md`), and an entry starting
    /// outside the range is out of scope for it entirely, the same way
    /// day-bucketing keys off `startDate` alone rather than splitting a
    /// span across the boundary it crosses.
    private func completedEntries(start: Date, end: Date, req: Request) async throws -> [TimeEntry] {
        try await TimeEntry.query(on: req.db)
            .filter(\.$startDate >= start)
            .filter(\.$startDate < end)
            .all()
            .filter { $0.endDate != nil }
    }

    /// Dense: `start`'s calendar day through `end`'s (exclusive), inclusive
    /// of every day in between, even one with nothing logged.
    private static func dayRows(entries: [TimeEntry], start: Date, end: Date) -> [WorkHoursRow] {
        let calendar = Calendar.current
        var totals: [Date: TimeInterval] = [:]
        for entry in entries {
            guard let endDate = entry.endDate else { continue }
            let day = calendar.startOfDay(for: entry.startDate)
            totals[day, default: 0] += endDate.timeIntervalSince(entry.startDate)
        }
        var days: [Date] = []
        var current = calendar.startOfDay(for: start)
        while current < end {
            days.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return days.map { .day(date: $0, totalSeconds: totals[$0] ?? 0) }
    }

    /// The four container dimensions, each folded per ADR-0005. Every Task/
    /// Project/Client/Course is loaded once, regardless of `groupBy` (a
    /// personal, single-owner dataset, not one that needs a narrower fetch)
    /// — a Client's fold needs *every* one of its Projects' totals, not
    /// just the ones a Time Entry happens to reference directly, or an
    /// indirectly-folded Client total could come out short.
    private func containerRows(
        groupBy: ContainerGroupBy, entries: [TimeEntry], req: Request
    ) async throws -> [WorkHoursRow] {
        var taskDirect: [UUID: TimeInterval] = [:]
        var projectDirect: [UUID: TimeInterval] = [:]
        var clientDirect: [UUID: TimeInterval] = [:]
        var courseDirect: [UUID: TimeInterval] = [:]
        for entry in entries {
            guard let endDate = entry.endDate, let container = entry.container else { continue }
            let seconds = endDate.timeIntervalSince(entry.startDate)
            switch container {
            case .task(let id): taskDirect[id, default: 0] += seconds
            case .project(let id): projectDirect[id, default: 0] += seconds
            case .client(let id): clientDirect[id, default: 0] += seconds
            case .course(let id): courseDirect[id, default: 0] += seconds
            }
        }

        let tasks = try await PCCTask.query(on: req.db).all()
        let projects = try await Project.query(on: req.db).all()
        let clients = try await PCCClient.query(on: req.db).all()
        let courses = try await Course.query(on: req.db).all()

        // A Project/Course's folded total is its own direct entries plus
        // every Task belonging to it's already-computed direct total
        // (ADR-0005) — a Task itself has nothing to fold in, so
        // `taskDirect` is used as-is rather than recursed into.
        // `parentID` picks whichever of `PCCTask.project`/`course` applies.
        func foldedTotals(
            direct: [UUID: TimeInterval], parentID: (PCCTask) -> UUID?
        ) -> [UUID: TimeInterval] {
            var totals = direct
            for task in tasks {
                guard let taskID = task.id, let parentID = parentID(task) else { continue }
                totals[parentID, default: 0] += taskDirect[taskID] ?? 0
            }
            return totals
        }
        let projectTotal = foldedTotals(direct: projectDirect) { $0.$project.id }
        let courseTotal = foldedTotals(direct: courseDirect) { $0.$course.id }
        var clientTotal = clientDirect
        for project in projects {
            guard let projectID = project.id, let clientID = project.$client.id else { continue }
            clientTotal[clientID, default: 0] += projectTotal[projectID] ?? 0
        }

        switch groupBy {
        case .task:
            return Self.sparseRows(
                WorkHoursRow.task,
                items: Self.namedTotals(tasks, id: { $0.id }, name: { $0.title }, total: taskDirect)
            )
        case .project:
            return Self.sparseRows(
                WorkHoursRow.project,
                items: Self.namedTotals(projects, id: { $0.id }, name: { $0.name }, total: projectTotal)
            )
        case .course:
            return Self.sparseRows(
                WorkHoursRow.course,
                items: Self.namedTotals(courses, id: { $0.id }, name: { $0.name }, total: courseTotal)
            )
        case .client:
            return Self.sparseRows(
                WorkHoursRow.client,
                items: Self.namedTotals(clients, id: { $0.id }, name: { $0.name }, total: clientTotal)
            )
        }
    }

    /// Pairs each of `models`'s id/name with its total from `total`
    /// (falling back to `0`) — one shared shape for all four
    /// `containerRows` branches instead of a near-identical `compactMap`
    /// repeated per branch.
    private static func namedTotals<M>(
        _ models: [M], id: (M) -> UUID?, name: (M) -> String, total: [UUID: TimeInterval]
    ) -> [NamedTotal] {
        models.compactMap { model in
            id(model).map { NamedTotal(id: $0, name: name(model), totalSeconds: total[$0] ?? 0) }
        }
    }

    /// Sparse: a zero-total container is dropped rather than emitted as a
    /// `0`-second row, unlike `dayRows`. Sorted by name for a stable,
    /// predictable ordering — nothing about "insertion order" is meaningful
    /// here the way it might be for, say, a chronological list.
    private static func sparseRows(
        _ makeRow: (UUID, String, TimeInterval) -> WorkHoursRow,
        items: [NamedTotal]
    ) -> [WorkHoursRow] {
        items
            .filter { $0.totalSeconds > 0 }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { makeRow($0.id, $0.name, $0.totalSeconds) }
    }
}
