import Foundation

/// How the owner's logged time divides across the two dashboards that now
/// own it (issue #91).
///
/// Splitting Work (#89) and School (#90) into separate screens means neither
/// one shows a true total of the owner's logged time: Work covers
/// Client-side work and deliberately filters Course-owned Projects out of
/// its tree, School covers coursework and deliberately ignores everything
/// else. Overview is the cross-cutting screen that summarises every other
/// section, so the grand total belongs there — and it has to be a *total*,
/// which means accounting for the time that belongs to neither dashboard as
/// well.
///
/// The two parts are exhaustive over every completed Time Entry in range,
/// which is what makes `totalSeconds` a true total rather than a subtotal:
/// a Time Entry "attaches to exactly one of Task, Project, Client, or
/// Course — required, never none, never more than one" (`CONTEXT.md`,
/// ADR-0004), enforced at write time by `TimeEntryController`, so there is
/// no third kind of logged time for a third part to hold.
public struct LoggedHoursSplit: Equatable, Sendable {
    /// Time the Work dashboard totals — logged against a Client, a
    /// Client-side Project, or a Task of one (including a Task with no
    /// container at all, which that screen files under "Unassigned").
    public let workSeconds: Double
    /// Time the School dashboard totals — logged against a Course, a
    /// Course-owned Project, or a Task that reaches a Course by either path
    /// (ticket #88).
    public let schoolSeconds: Double

    public var totalSeconds: Double { workSeconds + schoolSeconds }

    public init(workSeconds: Double, schoolSeconds: Double) {
        self.workSeconds = workSeconds
        self.schoolSeconds = schoolSeconds
    }
}

/// The cross-domain hours split, as pure logic with no view or view model
/// involved — the Overview counterpart to `WorkTree` and `SchoolBoard`, and
/// testable at this package's pure-logic seam (`LoggedHoursTests`) for the
/// same reason.
public enum LoggedHours {
    /// Divides the completed Time Entries starting inside `range` into the
    /// two dashboards' shares.
    ///
    /// Deliberately decides "is this coursework?" by calling
    /// `SchoolBoard.courseID(for:tasks:projects:)` rather than restating the
    /// rule: the School share is then the *same function* the School screen
    /// totals with, folding through Course-owned Projects and Tasks exactly
    /// as ADR-0005 (extended by ADR-0011) specifies, so the two can't drift
    /// apart as the containment rules evolve. Everything else is Work, which
    /// is sound precisely because a Time Entry always has a container
    /// (ADR-0004): "not coursework" and "Client-side work" are the same set.
    ///
    /// A running timer is excluded — it contributes to no total until it's
    /// stopped (`CONTEXT.md`) — matching both dashboards and the backend's
    /// own Work Hours rollup (`WorkHoursController.completedEntries`).
    ///
    /// The Work share's agreement with `WorkTree` rests on one schema
    /// invariant worth naming: `WorkTree.build` drops a Task whose
    /// `projectID` isn't among the Projects it was handed, while this counts
    /// that Task's entries as Work. The two can't actually disagree, because
    /// `PCCTask.project_id` is `onDelete: .setNull` (`CreatePCCTask`) — a
    /// Task can never persist pointing at a Project that's gone; it becomes
    /// container-less, which both this and `WorkTree`'s "Unassigned" node
    /// count. The only window where they'd differ is a stale client-side
    /// `projects` list, i.e. between two concurrent fetches of one load.
    public static func split(
        timeEntries: [TimeEntry], tasks: [PCCTask], projects: [Project],
        range: (start: Date, end: Date)
    ) -> LoggedHoursSplit {
        var work = 0.0
        var school = 0.0
        for entry in timeEntries {
            guard let endDate = entry.endDate else { continue }
            guard entry.startDate >= range.start, entry.startDate < range.end else { continue }
            let seconds = endDate.timeIntervalSince(entry.startDate)
            if SchoolBoard.courseID(for: entry, tasks: tasks, projects: projects) != nil {
                school += seconds
            } else {
                work += seconds
            }
        }
        return LoggedHoursSplit(workSeconds: work, schoolSeconds: school)
    }
}
