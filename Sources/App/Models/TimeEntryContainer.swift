import Foundation

/// `TimeEntry.task`/`project`/`client`/`course` read together as one value —
/// a Time Entry attaches to exactly one of these, required, never none,
/// never more than one (`docs/adr/0004-time-entry-container-includes-course.md`).
/// Unlike `TaskContainer`, there's no `.none` case: a Task's Project/Course
/// are each independently optional, but a Time Entry's container is
/// mandatory, so every `TimeEntryContainer` value names one of the four
/// attached targets. `TimeEntryController` is the single place that turns a
/// request's four independently-optional ids into one of these (rejecting
/// zero or multiple) and back.
enum TimeEntryContainer: Equatable {
    case task(UUID)
    case project(UUID)
    case client(UUID)
    case course(UUID)
}
