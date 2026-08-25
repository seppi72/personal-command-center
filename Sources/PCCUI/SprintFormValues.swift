import Foundation

/// The fields a Sprint create/edit form produces together — name and its
/// date range — bundled so `SprintsViewModel` and `SprintFormSheet` pass one
/// value instead of loose parameters that always travel as a set (mirrors
/// `ProjectFormValues`/`CourseFormValues`).
public struct SprintFormValues: Equatable, Sendable {
    public var name: String
    public var startDate: Date
    public var endDate: Date

    public init(name: String, startDate: Date, endDate: Date) {
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
    }
}
