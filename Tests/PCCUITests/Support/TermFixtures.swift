import Foundation

@testable import PCCUI

/// A Course carries its whole Term (`docs/adr/0012-term-is-an-entity.md`),
/// so every Course fixture in these suites needs one. Most of them don't
/// care which Term it is — they're testing hours, queues or Deadlines — so
/// this default keeps that noise out of their setup.
///
/// `displayName` is composed the way the backend derives it, since these
/// tests stand in for a decoded API response rather than building one
/// client-side.
func makeTerm(
    id: UUID = UUID(), year: Int = 2023, semester: Semester = .first, startDate: Date? = nil,
    endDate: Date? = nil
) -> Term {
    Term(
        id: id, year: year, semester: semester,
        displayName: "\(semester.displayName) \(year)", startDate: startDate, endDate: endDate)
}
