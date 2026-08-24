import Fluent
import Vapor

/// Spec #1's `CalendarSyncService` module: `push`/`remove` (ticket #6) send
/// Personal Commitment changes out to CalDAV synchronously, from
/// `PersonalCommitmentController`; `pull` (ticket #7) brings external
/// Calendar events in, and `pushPendingCommitments`/`runScheduledSync`
/// (ticket #7) are what the recurring background job
/// (`startCalendarSyncSchedule`, wired up in `configure.swift`) calls, so
/// both directions of sync also run on a schedule independent of either
/// client app being open (spec #1, user story 23).
struct CalendarSyncService {
    let calDAVClient: any CalDAVClient
    let db: any Database
    let logger: Logger

    /// Pushes `commitment`'s current fields to CalDAV under its existing
    /// `externalEventID` (a stable UID assigned once, at creation — CalDAV's
    /// `PUT` to a UID-addressed resource is naturally an upsert, so this one
    /// method serves both "create" and "edit"), updates `syncStatus` to
    /// match the outcome, and writes an `AutomationLog` entry either way.
    ///
    /// Never throws: `PersonalCommitment` is canonical (`CONTEXT.md`) — the
    /// Command Center owns this data, so a CalDAV failure is a logged,
    /// visible state (spec #1's "clear error state" requirement) rather
    /// than a reason to fail the caller's own write.
    func push(_ commitment: PersonalCommitment, action: String) async {
        let event = CalDAVEvent(
            uid: commitment.externalEventID,
            title: commitment.title,
            start: commitment.startDate,
            end: commitment.endDate,
            recurrenceRule: commitment.recurrenceRule
        )
        do {
            try await calDAVClient.upsertEvent(event)
            commitment.syncStatus = .synced
            try await commitment.save(on: db)
            await logCommitment(action: action, commitment: commitment, outcome: .success, detail: "Pushed to CalDAV")
        } catch {
            logger.warning("CalDAV push failed for PersonalCommitment \(commitment.id?.uuidString ?? "?"): \(error)")
            commitment.syncStatus = .failed
            do {
                try await commitment.save(on: db)
            } catch {
                logger.warning("Failed to record syncStatus=failed for PersonalCommitment \(commitment.id?.uuidString ?? "?"): \(error)")
            }
            await logCommitment(action: action, commitment: commitment, outcome: .failure, detail: "CalDAV push failed: \(error)")
        }
    }

    /// Removes `commitment`'s CalDAV event and logs the attempt. Call this
    /// before deleting `commitment`'s row, while its id is still available
    /// for the log entry's `subjectID`. Takes an `action` the same way
    /// `push` does, even though every current caller passes
    /// `"personal_commitment.delete"`, so the two methods read the same way
    /// at the call site rather than one hardcoding what the other parameterizes.
    func remove(_ commitment: PersonalCommitment, action: String) async {
        do {
            try await calDAVClient.deleteEvent(uid: commitment.externalEventID)
            await logCommitment(action: action, commitment: commitment, outcome: .success, detail: "Removed from CalDAV")
        } catch {
            logger.warning("CalDAV delete failed for PersonalCommitment \(commitment.id?.uuidString ?? "?"): \(error)")
            await logCommitment(action: action, commitment: commitment, outcome: .failure, detail: "CalDAV delete failed: \(error)")
        }
    }

    /// Pulls every event currently on the external Calendar into the
    /// read-only `MirroredCalendarEvent` cache (ticket #7) — the "pull"
    /// half of this module, alongside `push`/`remove`'s "push" half. Called
    /// from the recurring background job (`runScheduledSync`); there's no
    /// owner-facing "pull now" action the way `push` has an owner-facing
    /// create/edit.
    ///
    /// Upserts by `externalEventID` (a moved or renamed external event is
    /// still the same event id, just with different field values), so a
    /// repeated pull converges to whatever the external Calendar currently
    /// has instead of growing the cache forever. Never throws, same
    /// rationale as `push`/`remove`: a failed pull is a logged, visible
    /// state, not a reason to interrupt whatever's driving the schedule.
    ///
    /// Logs "the same as push actions" — one `AutomationLog` entry per
    /// affected `MirroredCalendarEvent`, `subjectID` pointing at that row's
    /// own id, exactly like `push` points `subjectID` at the Commitment it
    /// touched — rather than one entry per whole run against a synthetic
    /// id nothing else references. An event whose fields didn't change
    /// since the last pull is skipped, the same way `pushPendingCommitments`
    /// only calls `push` for a Commitment that actually needs it: most
    /// pulls, most of the time, touch nothing, and logging every unchanged
    /// event on every interval would flood the log without giving the
    /// owner anything new to act on. `lastSyncedAt` on every row (visible
    /// via `GET /v1/calendar-events`) is what confirms the pull itself
    /// keeps running even during a quiet stretch with nothing to log.
    ///
    /// The one exception is a pull that fails before fetching any events at
    /// all (`calDAVClient.fetchEvents()` itself throwing) — there's no
    /// affected row to hang that failure on, so that path alone logs
    /// against a freshly-minted id.
    func pull(action: String = "calendar.pull") async {
        let events: [CalDAVEvent]
        do {
            events = try await calDAVClient.fetchEvents()
        } catch {
            logger.warning("CalDAV pull failed: \(error)")
            await log(action: action, subjectType: "CalendarSync", subjectID: UUID(), outcome: .failure, detail: "CalDAV pull failed: \(error)")
            return
        }

        for event in events {
            do {
                try await upsertMirroredEvent(event, action: action)
            } catch {
                logger.warning("Failed to store pulled Calendar event \(event.uid): \(error)")
            }
        }
    }

    /// Upserts one pulled event and, only if it's new or its fields
    /// actually changed, writes the `AutomationLog` entry for it.
    private func upsertMirroredEvent(_ event: CalDAVEvent, action: String) async throws {
        let existing = try await MirroredCalendarEvent.query(on: db)
            .filter(\.$externalEventID == event.uid)
            .first()
        let mirrored = existing ?? MirroredCalendarEvent(
            externalEventID: event.uid,
            title: event.title,
            startDate: event.start,
            endDate: event.end
        )
        let isUnchanged = existing != nil
            && mirrored.title == event.title
            && mirrored.startDate == event.start
            && mirrored.endDate == event.end
        mirrored.title = event.title
        mirrored.startDate = event.start
        mirrored.endDate = event.end
        mirrored.lastSyncedAt = Date()
        try await mirrored.save(on: db)

        guard !isUnchanged else { return }
        let subjectID = try mirrored.requireID()
        let detail = existing == nil ? "Pulled new event from CalDAV" : "Updated mirrored event from CalDAV"
        await log(action: action, subjectType: "MirroredCalendarEvent", subjectID: subjectID, outcome: .success, detail: detail)
    }

    /// Re-attempts the CalDAV push for every Commitment not currently
    /// `.synced` (i.e. `.pending`, never yet pushed, or `.failed`, pushed
    /// and failed) — the recurring job's safety net for a push that failed
    /// transiently (e.g. iCloud briefly unreachable). Without this, a
    /// Commitment whose synchronous push (`PersonalCommitmentController`)
    /// failed would stay `.failed` forever with no owner action to retry
    /// it. Reuses `push`, so each retried Commitment gets its own
    /// `AutomationLog` entry the same way a controller-triggered push does.
    func pushPendingCommitments(action: String = "personal_commitment.scheduled_sync") async {
        let notYetSynced: [PersonalCommitment]
        do {
            notYetSynced = try await PersonalCommitment.query(on: db).all().filter { $0.syncStatus != .synced }
        } catch {
            logger.warning("Failed to query not-yet-synced Personal Commitments for scheduled push: \(error)")
            return
        }
        for commitment in notYetSynced {
            await push(commitment, action: action)
        }
    }

    /// The recurring background job's full unit of work (ticket #7):
    /// pull, then retry any not-yet-synced push. Order doesn't matter
    /// functionally; pulling first mirrors spec #1's own phrasing of user
    /// story 23 ("pulling in events and pushing out Commitments").
    func runScheduledSync() async {
        await pull()
        await pushPendingCommitments()
    }

    /// Best-effort: a logging failure shouldn't surface as an error from
    /// `push`/`remove`, which already promise not to throw — but it's still
    /// reported to `logger` so a double failure (CalDAV *and* the
    /// AutomationLog write) leaves a trace somewhere instead of vanishing.
    private func logCommitment(action: String, commitment: PersonalCommitment, outcome: AutomationLog.Outcome, detail: String) async {
        guard let subjectID = try? commitment.requireID() else { return }
        await log(action: action, subjectType: "PersonalCommitment", subjectID: subjectID, outcome: outcome, detail: detail)
    }

    private func log(action: String, subjectType: String, subjectID: UUID, outcome: AutomationLog.Outcome, detail: String) async {
        let entry = AutomationLog(
            actionType: action,
            subjectType: subjectType,
            subjectID: subjectID,
            detail: detail,
            outcome: outcome
        )
        do {
            try await entry.save(on: db)
        } catch {
            logger.warning("Failed to write AutomationLog entry for \(action) on \(subjectType) \(subjectID): \(error)")
        }
    }
}
