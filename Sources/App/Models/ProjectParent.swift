import Foundation

/// `Project.client`/`Project.course` as one value instead of a loose pair —
/// a Project belongs to at most one of {Client, Course}, never both
/// (ADR-0011). The same shape `TaskContainer` already gives
/// `PCCTask.project`/`course` (ADR-0003), reused here rather than inventing
/// a third mechanism: the exclusivity is a type `ProjectController`'s two
/// assignment endpoints route through, not a rule each re-derives from two
/// independent `UUID?`s.
enum ProjectParent: Equatable {
    case client(UUID)
    case course(UUID)
    case none
}
