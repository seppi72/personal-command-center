import Foundation

/// One Calendar event as CalDAV sees it — the currency `CalDAVClient` deals
/// in, independent of the `PersonalCommitment` Fluent model so this file has
/// no Fluent dependency.
struct CalDAVEvent: Equatable, Sendable {
    /// The iCalendar UID and, for `ICloudCalDAVClient`, the `.ics` resource
    /// name under the configured calendar collection. Assigned once, by the
    /// caller, at Commitment-creation time — see `PersonalCommitment.init`.
    let uid: String
    let title: String
    let start: Date
    let end: Date
    let recurrenceRule: String?
}

enum CalDAVClientError: Error {
    case serverError(status: Int)
}

/// Talks to the external Calendar's CalDAV endpoint (ADR-0002: iCloud,
/// authenticated with a server-held app-specific password — never shipped
/// to either client). A protocol so `CalendarSyncService` can be exercised
/// against a fake in tests rather than a live iCloud account (spec #1's
/// testing seam) — see `Tests/AppTests/Support/FakeCalDAVClient.swift`.
protocol CalDAVClient: Sendable {
    /// Creates the event at `event.uid` if it doesn't exist yet, or
    /// overwrites it if it does — CalDAV's `PUT` to a UID-addressed
    /// resource is naturally an upsert, so "create" and "edit" are the same
    /// operation from the client's point of view.
    func upsertEvent(_ event: CalDAVEvent) async throws
    func deleteEvent(uid: String) async throws

    /// Every event currently on the configured calendar collection — the
    /// "pull" half of ticket #7's sync (`CalendarSyncService.pull`), which
    /// upserts each one into the read-only `MirroredCalendarEvent` cache.
    func fetchEvents() async throws -> [CalDAVEvent]
}
