@testable import App

/// The fake `CalDAVClient` spec #1's testing seam calls for: records every
/// push/delete in memory instead of making a network call, rather than
/// exercising `PersonalCommitmentController` against a live iCloud account
/// (which would need real credentials and be flaky in CI).
///
/// An `actor` because `CalDAVClient` requires `Sendable` and its methods
/// run inside the app's request-handling context; recording calls needs
/// mutable state, so this needs its own isolation rather than piggybacking
/// on the caller's.
actor FakeCalDAVClient: CalDAVClient {
    enum Call: Equatable {
        case upsert(CalDAVEvent)
        case delete(uid: String)
        case fetch
    }

    private(set) var calls: [Call] = []

    /// When set, every call fails with this error instead of succeeding —
    /// how tests exercise `CalendarSyncService`'s failure path (logged
    /// `AutomationLog` entry, `syncStatus == .failed`) without a real
    /// network failure.
    var failureToThrow: (any Error)?

    /// What `fetchEvents()` returns — how tests exercise
    /// `CalendarSyncService.pull`'s success path without a real iCloud
    /// account. Empty until a test sets it.
    var eventsToReturn: [CalDAVEvent] = []

    init(failureToThrow: (any Error)? = nil, eventsToReturn: [CalDAVEvent] = []) {
        self.failureToThrow = failureToThrow
        self.eventsToReturn = eventsToReturn
    }

    func upsertEvent(_ event: CalDAVEvent) async throws {
        calls.append(.upsert(event))
        if let failureToThrow { throw failureToThrow }
    }

    func deleteEvent(uid: String) async throws {
        calls.append(.delete(uid: uid))
        if let failureToThrow { throw failureToThrow }
    }

    func fetchEvents() async throws -> [CalDAVEvent] {
        calls.append(.fetch)
        if let failureToThrow { throw failureToThrow }
        return eventsToReturn
    }

    func setFailureToThrow(_ error: (any Error)?) {
        failureToThrow = error
    }

    func setEventsToReturn(_ events: [CalDAVEvent]) {
        eventsToReturn = events
    }
}
