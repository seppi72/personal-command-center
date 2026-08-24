import Foundation
import Testing
import VaporTesting

@testable import App

/// Exercises `CalendarSyncService.pull`/`pushPendingCommitments`/
/// `runScheduledSync` directly against a real (test) Postgres database and
/// a `FakeCalDAVClient` (ticket #7's AC: "Tests use the fake CalDAV client
/// to exercise both pull and push against a real test database"). Unlike
/// `PersonalCommitmentTests`, there's no HTTP request to drive here — the
/// scheduled job (`startCalendarSyncSchedule`) has no owner-facing trigger,
/// so these tests call the Service methods the job itself calls, the same
/// way `startCalendarSyncSchedule` would.
// Serialized: shares `personal_commitments`/`automation_logs` with
// `PersonalCommitmentTests`, and owns `mirrored_calendar_events`.
extension AppTestSuite {
    @Suite("CalendarSyncService", .serialized)
    struct CalendarSyncServiceTests {
        @discardableResult
        private func withSyncApp<T>(
            caldav: FakeCalDAVClient = FakeCalDAVClient(),
            _ test: (Application, FakeCalDAVClient) async throws -> T
        ) async throws -> T {
            try await withApp(configure: { app in
                setenv("AUTH_TOKENS", "test-token-one", 1)
                app.calDAVClient = caldav
                try await configure(app)
            }) { app in
                let result = try await test(app, caldav)
                try await AutomationLog.query(on: app.db).delete()
                try await PersonalCommitment.query(on: app.db).delete()
                try await MirroredCalendarEvent.query(on: app.db).delete()
                return result
            }
        }

        private func syncService(_ app: Application, caldav: FakeCalDAVClient) -> CalendarSyncService {
            CalendarSyncService(calDAVClient: caldav, db: app.db, logger: app.logger)
        }

        private func logs(on app: Application, subjectType: String) async throws -> [AutomationLog] {
            try await AutomationLog.query(on: app.db).all().filter { $0.subjectType == subjectType }
        }

        // MARK: - pull

        @Test("pulls a new external Calendar event into the mirrored-event cache and logs it against that row's own id")
        func pullsExternalEvents() async throws {
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            let end = Date(timeIntervalSince1970: 1_800_003_600)
            let caldav = FakeCalDAVClient(eventsToReturn: [
                CalDAVEvent(uid: "ext-1", title: "Team Standup", start: start, end: end, recurrenceRule: nil)
            ])
            try await withSyncApp(caldav: caldav) { app, caldav in
                await syncService(app, caldav: caldav).pull()

                let mirrored = try await MirroredCalendarEvent.query(on: app.db).all()
                #expect(mirrored.count == 1)
                #expect(mirrored.first?.externalEventID == "ext-1")
                #expect(mirrored.first?.title == "Team Standup")
                #expect(mirrored.first?.startDate == start)
                #expect(mirrored.first?.endDate == end)

                // "Same as push actions" (ticket #7's AC): the log entry's
                // subjectID points at the real MirroredCalendarEvent row it
                // affected, exactly like a push's subjectID points at the
                // real Commitment it affected — not a synthetic id nothing
                // else references.
                let entries = try await logs(on: app, subjectType: "MirroredCalendarEvent")
                #expect(entries.count == 1)
                #expect(entries.first?.actionType == "calendar.pull")
                #expect(entries.first?.outcome == .success)
                #expect(entries.first?.subjectID == mirrored.first?.id)
                #expect(entries.first?.detail.contains("new event") == true)

                let calls = await caldav.calls
                #expect(calls == [.fetch])
            }
        }

        @Test("re-pulling the same external event updates the existing mirrored row instead of duplicating it")
        func pullUpsertsByExternalEventID() async throws {
            let caldav = FakeCalDAVClient(eventsToReturn: [
                CalDAVEvent(
                    uid: "ext-1",
                    title: "Original Title",
                    start: Date(timeIntervalSince1970: 1_800_000_000),
                    end: Date(timeIntervalSince1970: 1_800_003_600),
                    recurrenceRule: nil
                )
            ])
            try await withSyncApp(caldav: caldav) { app, caldav in
                let service = syncService(app, caldav: caldav)
                await service.pull()

                let newStart = Date(timeIntervalSince1970: 1_900_000_000)
                let newEnd = Date(timeIntervalSince1970: 1_900_003_600)
                await caldav.setEventsToReturn([
                    CalDAVEvent(uid: "ext-1", title: "Renamed", start: newStart, end: newEnd, recurrenceRule: nil)
                ])
                await service.pull()

                let mirrored = try await MirroredCalendarEvent.query(on: app.db).all()
                #expect(mirrored.count == 1)
                #expect(mirrored.first?.title == "Renamed")
                #expect(mirrored.first?.startDate == newStart)
                #expect(mirrored.first?.endDate == newEnd)

                // One entry for the initial pull ("new event"), one for the
                // second pull's actual change ("updated") — both against
                // the same row's id, since it's the same mirrored event
                // throughout.
                let entries = try await logs(on: app, subjectType: "MirroredCalendarEvent")
                #expect(entries.count == 2)
                #expect(entries.allSatisfy { $0.subjectID == mirrored.first?.id })
                #expect(entries.contains { $0.detail.contains("new event") })
                #expect(entries.contains { $0.detail.contains("Updated") })
            }
        }

        @Test("re-pulling an unchanged external event doesn't write another log entry")
        func pullSkipsLoggingUnchangedEvents() async throws {
            let event = CalDAVEvent(
                uid: "ext-1",
                title: "Steady",
                start: Date(timeIntervalSince1970: 1_800_000_000),
                end: Date(timeIntervalSince1970: 1_800_003_600),
                recurrenceRule: nil
            )
            let caldav = FakeCalDAVClient(eventsToReturn: [event])
            try await withSyncApp(caldav: caldav) { app, caldav in
                let service = syncService(app, caldav: caldav)
                await service.pull()

                let justBeforeSecondPull = Date()
                await service.pull()

                let mirrored = try await MirroredCalendarEvent.query(on: app.db).all()
                #expect(mirrored.count == 1)

                // Only the first pull's "new event" entry — the second
                // pull found nothing changed, so it wrote nothing more
                // (avoids flooding the log every interval with entries for
                // events that haven't moved). `lastSyncedAt` is still
                // touched on every pull regardless, which is what proves
                // the second, quiet pull actually ran.
                let entries = try await logs(on: app, subjectType: "MirroredCalendarEvent")
                #expect(entries.count == 1)
                #expect((mirrored.first?.lastSyncedAt ?? .distantPast) >= justBeforeSecondPull)
            }
        }

        @Test("a CalDAV pull failure stores no mirrored events and logs the failure against a synthetic subject")
        func pullFailureIsLoggedNotFatal() async throws {
            let caldav = FakeCalDAVClient(failureToThrow: CalDAVClientError.serverError(status: 503))
            try await withSyncApp(caldav: caldav) { app, caldav in
                await syncService(app, caldav: caldav).pull()

                let mirrored = try await MirroredCalendarEvent.query(on: app.db).all()
                #expect(mirrored.isEmpty)

                // No affected MirroredCalendarEvent row exists for this
                // failure to point at (the fetch itself failed, before any
                // event was seen) — the one case where the log entry falls
                // back to a synthetic subject.
                let entries = try await logs(on: app, subjectType: "CalendarSync")
                #expect(entries.count == 1)
                #expect(entries.first?.actionType == "calendar.pull")
                #expect(entries.first?.outcome == .failure)
                #expect(entries.first?.detail.contains("CalDAV pull failed") == true)
            }
        }

        // MARK: - pushPendingCommitments

        @Test("retries the push for pending and failed Commitments, but not already-synced ones")
        func pushesOnlyNotYetSyncedCommitments() async throws {
            try await withSyncApp { app, caldav in
                let pending = PersonalCommitment(
                    title: "Pending",
                    startDate: Date(timeIntervalSince1970: 1_800_000_000),
                    endDate: Date(timeIntervalSince1970: 1_800_003_600),
                    syncStatus: .pending
                )
                let failed = PersonalCommitment(
                    title: "Failed",
                    startDate: Date(timeIntervalSince1970: 1_800_000_000),
                    endDate: Date(timeIntervalSince1970: 1_800_003_600),
                    syncStatus: .failed
                )
                let synced = PersonalCommitment(
                    title: "Already Synced",
                    startDate: Date(timeIntervalSince1970: 1_800_000_000),
                    endDate: Date(timeIntervalSince1970: 1_800_003_600),
                    syncStatus: .synced
                )
                try await pending.save(on: app.db)
                try await failed.save(on: app.db)
                try await synced.save(on: app.db)

                await syncService(app, caldav: caldav).pushPendingCommitments()

                let calls = await caldav.calls
                let pushedUIDs = calls.compactMap { call -> String? in
                    if case let .upsert(event) = call { return event.uid }
                    return nil
                }
                #expect(Set(pushedUIDs) == Set([pending.externalEventID, failed.externalEventID]))

                let refreshedPending = try await PersonalCommitment.find(pending.requireID(), on: app.db)
                let refreshedFailed = try await PersonalCommitment.find(failed.requireID(), on: app.db)
                #expect(refreshedPending?.syncStatus == .synced)
                #expect(refreshedFailed?.syncStatus == .synced)

                let entries = try await AutomationLog.query(on: app.db).all()
                    .filter { $0.actionType == "personal_commitment.scheduled_sync" }
                #expect(entries.count == 2)
            }
        }

        @Test("does nothing when every Commitment is already synced")
        func pushSkipsWhenNothingPending() async throws {
            try await withSyncApp { app, caldav in
                let synced = PersonalCommitment(
                    title: "Already Synced",
                    startDate: Date(timeIntervalSince1970: 1_800_000_000),
                    endDate: Date(timeIntervalSince1970: 1_800_003_600),
                    syncStatus: .synced
                )
                try await synced.save(on: app.db)

                await syncService(app, caldav: caldav).pushPendingCommitments()

                let calls = await caldav.calls
                #expect(calls.isEmpty)
            }
        }

        // MARK: - runScheduledSync

        @Test("runScheduledSync pulls external events and retries not-yet-synced Commitment pushes together")
        func runScheduledSyncDoesBoth() async throws {
            let caldav = FakeCalDAVClient(eventsToReturn: [
                CalDAVEvent(
                    uid: "ext-1",
                    title: "Mirrored",
                    start: Date(timeIntervalSince1970: 1_800_000_000),
                    end: Date(timeIntervalSince1970: 1_800_003_600),
                    recurrenceRule: nil
                )
            ])
            try await withSyncApp(caldav: caldav) { app, caldav in
                let pending = PersonalCommitment(
                    title: "Pending",
                    startDate: Date(timeIntervalSince1970: 1_800_000_000),
                    endDate: Date(timeIntervalSince1970: 1_800_003_600),
                    syncStatus: .pending
                )
                try await pending.save(on: app.db)

                await syncService(app, caldav: caldav).runScheduledSync()

                let mirrored = try await MirroredCalendarEvent.query(on: app.db).all()
                #expect(mirrored.count == 1)

                let refreshedPending = try await PersonalCommitment.find(pending.requireID(), on: app.db)
                #expect(refreshedPending?.syncStatus == .synced)

                let calls = await caldav.calls
                #expect(calls.contains(.fetch))
                #expect(calls.contains { if case .upsert = $0 { return true } else { return false } })
            }
        }
    }
}
