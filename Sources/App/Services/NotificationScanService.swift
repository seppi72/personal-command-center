import Fluent
import Vapor

/// Ticket #47's overdue-Deadline scan: keeps `PCCNotification` (ticket #46's
/// "needs you" queue) in sync with which Tasks, Projects, and Courses are
/// currently overdue. Runs on `NotificationScanSchedule`'s recurring
/// interval; tested here directly rather than through the schedule's loop,
/// the same way `CalendarSyncServiceTests` exercises `CalendarSyncService`
/// rather than `CalendarSyncSchedule`.
struct NotificationScanService {
    let db: any Database
    let logger: Logger

    /// One overdue source item, flattened enough to build a Notification
    /// from. `sourceType` matches the Swift model's own type name (e.g.
    /// `"PCCTask"`) — the same string `PCCNotification.sourceType` already
    /// stores for it (`NotificationTests`' fixtures use `"PCCTask"`) — while
    /// `label` is the human-readable kind word the message text uses
    /// (`"Task"`, not `"PCCTask"`).
    private struct OverdueItem {
        let sourceType: String
        let label: String
        let sourceID: UUID
        let title: String
    }

    /// Identifies one `PCCNotification`'s source item by the same
    /// `sourceType`/`sourceID` pair the model itself stores, so a fetched
    /// `OverdueItem` and a fetched `PCCNotification` row can be compared for
    /// dedup/auto-clear without caring which one produced the pair.
    private struct SourceKey: Hashable {
        let sourceType: String
        let sourceID: UUID
    }

    /// The `sourceType` strings this scan owns — every `OverdueItem.sourceType`
    /// above is one of these, kept in one place so the create pass (which
    /// stamps them) and the reconcile pass (which filters by them) can't
    /// silently drift apart. Also what scopes this scan to Deadline-sourced
    /// rows only, so it never touches an `AutomationLog`-sourced Notification
    /// (ticket #48's job, deduped differently — see that ticket's own AC).
    private static let deadlineSourceTypes: Set<String> = [Self.taskSourceType, Self.projectSourceType, Self.courseSourceType]
    private static let taskSourceType = "PCCTask"
    private static let projectSourceType = "Project"
    private static let courseSourceType = "Course"

    /// Queries every currently-overdue Task/Project/Course (reusing
    /// `DeadlineController`'s own "all three, flattened" query shape, plus
    /// the past-due-date filter), then reconciles `PCCNotification` against
    /// that set: creates one for an overdue item with no open Notification
    /// already pointing at it, and auto-clears (dismisses) any open
    /// Deadline-sourced Notification whose item is no longer in that set —
    /// completed, pushed to the future, or deleted. Never throws: a failed
    /// scan is logged and simply tries again next interval, the same
    /// never-fail-the-caller posture `CalendarSyncService.pull` takes.
    func scan() async {
        let overdue: [OverdueItem]
        do {
            overdue = try await overdueItems()
        } catch {
            logger.warning("Failed to query overdue Deadlines for Notification scan: \(error)")
            return
        }

        do {
            try await reconcile(overdue: overdue)
        } catch {
            logger.warning("Failed to reconcile Notifications for overdue Deadlines: \(error)")
        }
    }

    /// Fluent has no cross-model UNION here, so all three tables are fetched
    /// and merged in memory — the same tradeoff `DeadlineController.index`
    /// already makes at this system's single-user scale (`CONTEXT.md`).
    /// Filtering `dueDate < now` at the database naturally excludes undated
    /// (`nil`) items along with future-dated ones.
    private func overdueItems() async throws -> [OverdueItem] {
        let now = Date()
        async let tasks = PCCTask.query(on: db)
            .filter(\.$isComplete == false)
            .filter(\.$dueDate < now)
            .all()
        async let projects = Project.query(on: db)
            .filter(\.$dueDate < now)
            .all()
        async let courses = Course.query(on: db)
            .filter(\.$dueDate < now)
            .all()

        let taskItems = try await tasks.map {
            try OverdueItem(sourceType: Self.taskSourceType, label: "Task", sourceID: $0.requireID(), title: $0.title)
        }
        let projectItems = try await projects.map {
            try OverdueItem(sourceType: Self.projectSourceType, label: "Project", sourceID: $0.requireID(), title: $0.name)
        }
        let courseItems = try await courses.map {
            try OverdueItem(sourceType: Self.courseSourceType, label: "Course", sourceID: $0.requireID(), title: $0.name)
        }
        return taskItems + projectItems + courseItems
    }

    /// Dedup only ever looks at currently-*open* Notifications — never at
    /// dismissed history — so a Notification the owner dismissed while its
    /// item was still overdue can be followed by a fresh one on a later
    /// scan; what stays true is that the dismissed row itself is never
    /// flipped back to open (User Story 10's actual guarantee). This is
    /// also why an `AutomationLog`-sourced Notification (ticket #48) is
    /// untouched here: `deadlineSourceTypes` scopes both the auto-clear and
    /// the create pass to Deadline-sourced rows only.
    private func reconcile(overdue: [OverdueItem]) async throws {
        let overdueKeys = Set(overdue.map { SourceKey(sourceType: $0.sourceType, sourceID: $0.sourceID) })
        let openDeadlineNotifications = try await PCCNotification.query(on: db)
            .filter(\.$isDismissed == false)
            .all()
            .filter { Self.deadlineSourceTypes.contains($0.sourceType) }

        for notification in openDeadlineNotifications {
            let key = SourceKey(sourceType: notification.sourceType, sourceID: notification.sourceID)
            guard !overdueKeys.contains(key) else { continue }
            notification.isDismissed = true
            try await notification.save(on: db)
        }

        let stillOpenKeys = Set(
            openDeadlineNotifications
                .map { SourceKey(sourceType: $0.sourceType, sourceID: $0.sourceID) }
                .filter { overdueKeys.contains($0) }
        )
        for item in overdue {
            let key = SourceKey(sourceType: item.sourceType, sourceID: item.sourceID)
            guard !stillOpenKeys.contains(key) else { continue }
            let notification = PCCNotification(
                sourceType: item.sourceType,
                sourceID: item.sourceID,
                message: "\(item.label) '\(item.title)' is overdue"
            )
            try await notification.save(on: db)
        }
    }
}
