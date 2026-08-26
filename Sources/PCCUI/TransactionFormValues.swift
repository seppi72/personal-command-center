import Foundation

/// The fields a Transaction create/edit form produces together — the
/// Account it's logged against, an amount, a type, a date, and optional
/// notes — bundled so `TransactionsViewModel` and `TransactionFormSheet`
/// pass one value instead of five loose parameters that always travel as a
/// set (mirrors `AccountFormValues`). `accountID` is `nil` only transiently,
/// before the owner has picked one — `TransactionFormSheet` disables Save
/// until it's set, the same "form can transiently hold none selected" shape
/// `TimeEntryFormValues`' own container fields have, narrowed here to
/// Transaction's single required container.
public struct TransactionFormValues: Equatable, Sendable {
    public var accountID: UUID?
    public var amount: Double
    public var type: TransactionType
    public var date: Date
    public var notes: String?

    public init(
        accountID: UUID? = nil,
        amount: Double,
        type: TransactionType,
        date: Date = Date(),
        notes: String? = nil
    ) {
        self.accountID = accountID
        self.amount = amount
        self.type = type
        self.date = date
        self.notes = notes
    }
}
