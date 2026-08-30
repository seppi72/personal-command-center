import Foundation

/// The fields a Personal Commitment create/edit form produces together —
/// bundled so `PersonalCommitmentsViewModel` and the form sheet pass one
/// value instead of four loose parameters that always travel as a set
/// (mirrors `TaskFormValues`).
public struct PersonalCommitmentFormValues: Equatable, Sendable {
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var recurrenceRule: String?

    /// The Course this Commitment is a class meeting for, if any (ticket
    /// #56) — `nil` for an ordinary, non-school Commitment.
    public var courseID: UUID?

    public init(
        title: String,
        startDate: Date,
        endDate: Date,
        recurrenceRule: String? = nil,
        courseID: UUID? = nil
    ) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.recurrenceRule = recurrenceRule
        self.courseID = courseID
    }
}
