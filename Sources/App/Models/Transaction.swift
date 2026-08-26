import Fluent
import Vapor

/// Whether a Transaction moves money out of its Account (`.expense`) or into
/// it (`.income`) — carries the sign; `Transaction.amount` itself is always a
/// positive magnitude (ticket #37).
enum TransactionType: String, Codable, CaseIterable, Sendable {
    case expense, income
}

/// A single logged movement of money against exactly one Account
/// (`CONTEXT.md`), signed as an expense or income. Ticket #37 gives it
/// `accountID`/`amount`/`type`/`date`/`notes` only — `categoryID`/
/// `subcategoryID` are ticket #39's addition, once Category exists.
///
/// `type` is stored as its raw `String` rather than through Fluent's
/// `@Enum`, the same "plain column, translate at the edges" choice
/// `Account.typeRawValue` already made.
///
/// `account_id` is a required, non-optional `@Parent` — unlike `TimeEntry`'s
/// four independently-optional container foreign keys, a Transaction has
/// exactly one possible container, so there's no "exactly one of N" to
/// enforce. Its FK uses `.cascade` (`CreateTransaction`), matching
/// `TimeEntry`'s own FKs: `AccountController.delete` now guards against a
/// referencing Transaction (ticket #38), so this cascade is a
/// database-level fallback only, not reachable through the API, the same
/// way `TimeEntry`'s FKs already are.
final class Transaction: Model, @unchecked Sendable {
    static let schema = "transactions"

    @ID(key: .id)
    var id: UUID?

    /// Always a positive magnitude — `type` carries the sign (`signedAmount`),
    /// never this field itself.
    @Field(key: "amount")
    var amount: Double

    @Field(key: "type")
    var typeRawValue: String

    @Field(key: "date")
    var date: Date

    @OptionalField(key: "notes")
    var notes: String?

    @Parent(key: "account_id")
    var account: Account

    var type: TransactionType {
        get {
            guard let type = TransactionType(rawValue: typeRawValue) else {
                preconditionFailure("Unknown stored TransactionType raw value: \(typeRawValue)")
            }
            return type
        }
        set { typeRawValue = newValue.rawValue }
    }

    /// `amount` with `type`'s sign applied — an expense subtracts from its
    /// Account's Balance, income adds to it
    /// (`docs/adr/0007-computed-balance-over-reconciliation.md`).
    var signedAmount: Double {
        switch type {
        case .expense: return -amount
        case .income: return amount
        }
    }

    init() {}

    init(
        id: UUID? = nil,
        amount: Double,
        type: TransactionType,
        date: Date,
        notes: String? = nil,
        accountID: UUID
    ) {
        self.id = id
        self.amount = amount
        self.typeRawValue = type.rawValue
        self.date = date
        self.notes = notes
        self.$account.id = accountID
    }

    /// An Account's Balance is `openingBalance + Σ(signedAmount)` over every
    /// Transaction logged against it (`CONTEXT.md`), computed live, never
    /// stored. Loads every matching row and sums in Swift — same
    /// "aggregate in memory" shape `WorkHoursController` already uses for
    /// its own rollups — rather than a database-level `SUM`, since the sign
    /// depends on `type`, not just the raw `amount` column.
    static func netAmount(forAccount accountID: UUID, on database: any Database) async throws -> Double {
        try await Transaction.query(on: database)
            .filter(\.$account.$id == accountID)
            .all()
            .reduce(0) { $0 + $1.signedAmount }
    }

    /// Every Account's net Transaction sum, keyed by `account_id`, in one
    /// query — the "load once, aggregate in memory" shape
    /// `WorkHoursController`'s own rollups already use. `AccountController.index`
    /// uses this instead of calling `netAmount(forAccount:)` once per
    /// Account, which would make one database round trip per row listed.
    static func netAmountsByAccount(on database: any Database) async throws -> [UUID: Double] {
        try await Transaction.query(on: database).all().reduce(into: [:]) { totals, transaction in
            totals[transaction.$account.id, default: 0] += transaction.signedAmount
        }
    }
}
