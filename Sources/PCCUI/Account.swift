import Foundation

/// Client-side mirror of the backend's `AccountType`
/// (`Sources/App/Models/Account.swift`) — one of Account's six kinds
/// (`CONTEXT.md`). Raw values match the backend's wire format exactly.
public enum AccountType: String, Codable, CaseIterable, Sendable {
    case checking, savings, cash, creditCard, investment, loan

    /// Title-case label for picker/list display — `CONTEXT.md`'s own
    /// vocabulary, not the camelCase wire value.
    public var displayName: String {
        switch self {
        case .checking: return "Checking"
        case .savings: return "Savings"
        case .cash: return "Cash"
        case .creditCard: return "Credit Card"
        case .investment: return "Investment"
        case .loan: return "Loan"
        }
    }
}

/// Client-side mirror of the backend's `AccountClassification` — whether an
/// Account counts as an asset or a liability for Net Worth purposes
/// (`CONTEXT.md`). Server-computed from `AccountType`, never set by this
/// client; carried here purely for display.
public enum AccountClassification: String, Codable, Sendable {
    case asset, liability
}

/// Client-side mirror of the backend's `AccountResponse` — a named store of
/// money the owner tracks (`CONTEXT.md`). `balance` is server-computed
/// (`openingBalance` today, trivially — no Transactions exist yet to sum);
/// this type never recomputes it locally.
public struct Account: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var type: AccountType
    public var classification: AccountClassification
    public var openingBalance: Double
    public var balance: Double

    public init(
        id: UUID, name: String, type: AccountType, classification: AccountClassification,
        openingBalance: Double, balance: Double
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.classification = classification
        self.openingBalance = openingBalance
        self.balance = balance
    }
}
