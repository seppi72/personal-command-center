import Fluent
import Vapor

struct AutomationLogResponse: Content {
    let id: UUID
    let actionType: String
    let subjectType: String
    let subjectID: UUID
    let detail: String
    let outcome: String
    let occurredAt: Date

    init(_ log: AutomationLog) throws {
        self.id = try log.requireID()
        self.actionType = log.actionType
        self.subjectType = log.subjectType
        self.subjectID = log.subjectID
        self.detail = log.detail
        self.outcome = log.outcome.rawValue
        self.occurredAt = log.occurredAtOrDistantPast
    }
}

/// Ticket #8's payload: `entries` for the "recent activity" list, plus
/// `mostRecentFailure` singled out so a failure buried past `entries`' limit
/// still surfaces (spec #1's "clear error state rather than failing
/// silently" requirement) instead of only showing up if it happens to be
/// recent enough to make the list.
struct AutomationLogsResponse: Content {
    let entries: [AutomationLogResponse]
    let mostRecentFailure: AutomationLogResponse?
}

/// Read-only Automation Log endpoint (ticket #8): lets the owner see what
/// the system did on its own — every `AutomationLog` entry written by
/// `CalendarSyncService`'s `push`/`remove`/`pull` (and whatever automation
/// lands next, per spec #1) — with the most recent sync failure, if any,
/// singled out rather than left to be spotted by scrolling.
struct AutomationLogController: RouteCollection {
    /// How many of the most recent entries `index` returns in `entries` —
    /// enough for "recent activity" to be useful without shipping this
    /// system's entire audit trail on every request. `mostRecentFailure` is
    /// computed separately and isn't bounded by this limit, so a failure
    /// doesn't go unnoticed just because it scrolled out of the recent list.
    static let recentEntryLimit = 100

    func boot(routes: any RoutesBuilder) throws {
        routes.grouped("automation-logs").get(use: index)
    }

    /// Fetches every row and sorts/filters in memory rather than pushing
    /// `ORDER BY`/`WHERE outcome = ...` into the query — `outcome`'s backing
    /// field is private to `AutomationLog` (same tradeoff as querying
    /// `PersonalCommitment.syncStatus` elsewhere in this codebase), and this
    /// system's single-user scale (`CONTEXT.md`) makes an in-memory pass a
    /// fine cost for that simplicity.
    func index(req: Request) async throws -> AutomationLogsResponse {
        let all = try await AutomationLog.query(on: req.db).all()
        let sorted = all.sorted { $0.occurredAtOrDistantPast > $1.occurredAtOrDistantPast }
        let entries = try sorted.prefix(Self.recentEntryLimit).map(AutomationLogResponse.init)
        let mostRecentFailure = try sorted.first { $0.outcome == .failure }.map(AutomationLogResponse.init)
        return AutomationLogsResponse(entries: entries, mostRecentFailure: mostRecentFailure)
    }
}
