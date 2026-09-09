import Fluent
import Foundation

@testable import App

/// A Course belongs to exactly one Term, required
/// (`docs/adr/0012-term-is-an-entity.md`), so every test that needs a Course
/// needs a Term behind it. These two helpers keep that from being three
/// lines of setup at every such call site.
///
/// `makeTerm` is get-or-create rather than a plain insert: a Term is unique
/// on year plus semester (`CreateTerm`), and these suites share one real
/// Postgres database whose rows outlive an individual test's cleanup, so a
/// second insert of the same semester would fail on the unique index.
@discardableResult
func makeTerm(
    on db: any Database, year: Int = 2026, semester: Semester = .first,
    startDate: Date? = nil, endDate: Date? = nil
) async throws -> Term {
    if let existing = try await Term.query(on: db)
        .filter(\.$year == year)
        .filter(\.$semesterRawValue == semester.rawValue)
        .first()
    {
        existing.startDate = startDate
        existing.endDate = endDate
        try await existing.save(on: db)
        return existing
    }
    let term = Term(year: year, semester: semester, startDate: startDate, endDate: endDate)
    try await term.save(on: db)
    return term
}

/// A saved Course in a saved Term — the shape almost every suite's setup
/// wants. Returns the Course already persisted, so callers that used to
/// build one and save it separately can drop the save.
@discardableResult
func makeCourse(
    name: String, on db: any Database, dueDate: Date? = nil, year: Int = 2026,
    semester: Semester = .first, units: Double = 3, grade: Grade? = nil
) async throws -> Course {
    let term = try await makeTerm(on: db, year: year, semester: semester)
    let course = Course(
        name: name, termID: try term.requireID(), units: units, grade: grade, dueDate: dueDate)
    try await course.save(on: db)
    course.$term.value = term
    return course
}
