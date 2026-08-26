import Fluent
import Vapor

/// One of Account's six kinds (`CONTEXT.md`) — Checking, Savings, Cash, and
/// Investment classify as an asset; Credit Card and Loan classify as a
/// liability, for Net Worth purposes. The mapping is fixed, not
/// owner-configurable (ticket #36) — `classification` is a computed
/// property, never a separate stored field a request could set
/// independently of `type`.
///
/// Raw values are camelCase to match this API's existing JSON convention
/// (e.g. `WorkHoursGroupBy`'s query-string values, `clientID`/`dueDate`
/// field names) rather than the `snake_case`/`Title Case` `CONTEXT.md`
/// prose uses for "Credit Card".
enum AccountType: String, Codable, CaseIterable, Sendable {
    case checking, savings, cash, creditCard, investment, loan

    var classification: AccountClassification {
        switch self {
        case .checking, .savings, .cash, .investment: return .asset
        case .creditCard, .loan: return .liability
        }
    }
}

/// Whether an Account counts toward or against Net Worth (`CONTEXT.md`) —
/// derived from `AccountType.classification`, never stored or set directly.
enum AccountClassification: String, Codable, Sendable {
    case asset, liability
}

/// A named store of money the owner tracks (`CONTEXT.md`) — Checking,
/// Savings, Cash, Credit Card, Investment, or Loan — created directly by the
/// owner, not auto-detected (`docs/adr/0006-manual-entry-over-bank-aggregation-for-finances.md`).
///
/// `type` is stored as its raw `String` rather than through Fluent's
/// `@Enum`/`.enum(...)` (a native Postgres enum type): that path needs its
/// own migration-time `database.enum(...)` definition and a matching column
/// data type, machinery every other enum-shaped value in this codebase
/// (e.g. `WorkHoursGroupBy`) already avoids by living outside the database
/// entirely. `typeRawValue` plus the `type` computed accessor keeps the
/// same "plain column, translate at the edges" shape while still giving
/// callers a proper `AccountType` to work with.
///
/// `openingBalance` is set once at creation and never edited after
/// (`docs/adr/0007-computed-balance-over-reconciliation.md`) — there is no
/// setter exposed for it beyond the model's own initializer;
/// `AccountController.update` never touches it.
///
/// Collides with nothing in Vapor/Fluent/the stdlib, unlike `PCCClient`/
/// `PCCTask` — named plainly `Account`.
final class Account: Model, @unchecked Sendable {
    static let schema = "accounts"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    @Field(key: "type")
    var typeRawValue: String

    @Field(key: "opening_balance")
    var openingBalance: Double

    var type: AccountType {
        get {
            guard let type = AccountType(rawValue: typeRawValue) else {
                preconditionFailure("Unknown stored AccountType raw value: \(typeRawValue)")
            }
            return type
        }
        set { typeRawValue = newValue.rawValue }
    }

    init() {}

    init(id: UUID? = nil, name: String, type: AccountType, openingBalance: Double) {
        self.id = id
        self.name = name
        self.typeRawValue = type.rawValue
        self.openingBalance = openingBalance
    }
}
