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
    }

    private(set) var calls: [Call] = []

    /// When set, every call fails with this error instead of succeeding —
    /// how tests exercise `CalendarSyncService`'s failure path (logged
    /// `AutomationLog` entry, `syncStatus == .failed`) without a real
    /// network failure.
    var failureToThrow: (any Error)?

    init(failureToThrow: (any Error)? = nil) {
        self.failureToThrow = failureToThrow
    }

    func upsertEvent(_ event: CalDAVEvent) async throws {
        calls.append(.upsert(event))
        if let failureToThrow { throw failureToThrow }
    }

    func deleteEvent(uid: String) async throws {
        calls.append(.delete(uid: uid))
        if let failureToThrow { throw failureToThrow }
    }

    func setFailureToThrow(_ error: (any Error)?) {
        failureToThrow = error
    }
}
