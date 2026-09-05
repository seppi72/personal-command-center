import Foundation

/// The fields a Course create/edit form produces together — name, Term, and
/// the Deadline to attach/change/clear — bundled so `SchoolViewModel` and
/// `CourseFormSheet` pass one value instead of loose parameters that always
/// travel as a set (mirrors `ProjectFormValues`).
public struct CourseFormValues: Equatable, Sendable {
    public var name: String
    public var termMonth: Int
    public var termYear: Int
    public var dueDate: Date?

    public init(name: String, termMonth: Int, termYear: Int, dueDate: Date? = nil) {
        self.name = name
        self.termMonth = termMonth
        self.termYear = termYear
        self.dueDate = dueDate
    }
}
