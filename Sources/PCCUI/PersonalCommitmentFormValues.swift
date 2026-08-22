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

    public init(title: String, startDate: Date, endDate: Date, recurrenceRule: String? = nil) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.recurrenceRule = recurrenceRule
    }
}
