import Fluent
import Vapor

/// The "push a Personal Commitment out" half of spec #1's `CalendarSyncService`
/// module. Pulling external events in, and running this on a recurring
/// schedule rather than synchronously per-request, are ticket #7's job.
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
            await log(action: action, commitment: commitment, outcome: .success, detail: "Pushed to CalDAV")
        } catch {
            logger.warning("CalDAV push failed for PersonalCommitment \(commitment.id?.uuidString ?? "?"): \(error)")
            commitment.syncStatus = .failed
            do {
                try await commitment.save(on: db)
            } catch {
                logger.warning("Failed to record syncStatus=failed for PersonalCommitment \(commitment.id?.uuidString ?? "?"): \(error)")
            }
            await log(action: action, commitment: commitment, outcome: .failure, detail: "CalDAV push failed: \(error)")
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
            await log(action: action, commitment: commitment, outcome: .success, detail: "Removed from CalDAV")
        } catch {
            logger.warning("CalDAV delete failed for PersonalCommitment \(commitment.id?.uuidString ?? "?"): \(error)")
            await log(action: action, commitment: commitment, outcome: .failure, detail: "CalDAV delete failed: \(error)")
        }
    }

    /// Best-effort: a logging failure shouldn't surface as an error from
    /// `push`/`remove`, which already promise not to throw — but it's still
    /// reported to `logger` so a double failure (CalDAV *and* the
    /// AutomationLog write) leaves a trace somewhere instead of vanishing.
    private func log(action: String, commitment: PersonalCommitment, outcome: AutomationLog.Outcome, detail: String) async {
        guard let subjectID = try? commitment.requireID() else { return }
        let entry = AutomationLog(
            actionType: action,
            subjectType: "PersonalCommitment",
            subjectID: subjectID,
            detail: detail,
            outcome: outcome
        )
        do {
            try await entry.save(on: db)
        } catch {
            logger.warning("Failed to write AutomationLog entry for \(action) on PersonalCommitment \(subjectID): \(error)")
        }
    }
}
