import Foundation

/// The fields a Course create/edit form produces together — name, Term, and
/// the Deadline to attach/change/clear — bundled so `SchoolViewModel` and
/// `CourseFormSheet` pass one value instead of loose parameters that always
/// travel as a set (mirrors `ProjectFormValues`).
///
/// The Term is an id: a Course points at an existing Term rather than
/// describing one, so the form picks from the Terms already created rather
/// than spelling out a month and year of its own
/// (`docs/adr/0012-term-is-an-entity.md`).
public struct CourseFormValues: Equatable, Sendable {
    public var name: String
    public var termID: UUID
    public var dueDate: Date?

    public init(name: String, termID: UUID, dueDate: Date? = nil) {
        self.name = name
        self.termID = termID
        self.dueDate = dueDate
    }
}

/// The fields a Term create/edit form produces together — its identity (year
/// plus semester) and the calendar span the school publishes for it.
///
/// `startDate`/`endDate` travel as a pair: the backend rejects one without
/// the other, since half a span can neither be overlap-checked nor asked
/// whether it contains today (`TermController.validatedSpan`).
public struct TermFormValues: Equatable, Sendable {
    public var year: Int
    public var semester: Semester
    public var startDate: Date?
    public var endDate: Date?

    public init(year: Int, semester: Semester, startDate: Date? = nil, endDate: Date? = nil) {
        self.year = year
        self.semester = semester
        self.startDate = startDate
        self.endDate = endDate
    }
}
