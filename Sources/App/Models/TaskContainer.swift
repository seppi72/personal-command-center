import Foundation

/// `PCCTask.project`/`PCCTask.course` as one value instead of a loose pair —
/// a Task belongs to at most one of {Project, Course}, never both (ADR-0003).
/// Bundling them here makes "at most one of these two" a type
/// `TaskController.assignProject`/`assignCourse` route through, rather than
/// a rule each of the two endpoints re-derives from two independent
/// `UUID?`s.
enum TaskContainer: Equatable {
    case project(UUID)
    case course(UUID)
    case none
}
