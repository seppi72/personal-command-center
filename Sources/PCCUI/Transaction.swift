import Foundation

/// Client-side mirror of the backend's `TransactionType`
/// (`Sources/App/Models/Transaction.swift`) — whether a Transaction moves
/// money out of its Account (`.expense`) or into it (`.income`).
public enum TransactionType: String, Codable, CaseIterable, Sendable {
    case expense, income

    /// Title-case label for picker/list display — the same
    /// `AccountType.displayName` shape.
    public var displayName: String {
        switch self {
        case .expense: return "Expense"
        case .income: return "Income"
        }
    }
}

/// Client-side mirror of the backend's `TransactionResponse` — a single
/// logged movement of money against exactly one Account (`CONTEXT.md`).
/// Ticket #37 gave it `accountID`/`amount`/`type`/`date`/`notes`; ticket #39
/// adds the optional `categoryID`/`subcategoryID` tagging.
public struct Transaction: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var accountID: UUID
    public var amount: Double
    public var type: TransactionType
    public var date: Date
    public var notes: String?
    public var categoryID: UUID?
    public var subcategoryID: UUID?

    public init(
        id: UUID,
        accountID: UUID,
        amount: Double,
        type: TransactionType,
        date: Date,
        notes: String? = nil,
        categoryID: UUID? = nil,
        subcategoryID: UUID? = nil
    ) {
        self.id = id
        self.accountID = accountID
        self.amount = amount
        self.type = type
        self.date = date
        self.notes = notes
        self.categoryID = categoryID
        self.subcategoryID = subcategoryID
    }
}
