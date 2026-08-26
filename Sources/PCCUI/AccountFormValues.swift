import Foundation

/// The fields an Account create/edit form produces together — name, type,
/// and (create only) opening balance — bundled so `AccountsViewModel` and
/// `AccountFormSheet` pass one value instead of loose parameters that
/// always travel as a set (mirrors `ProjectFormValues`). `openingBalance` is
/// carried here even on an edit for a uniform shape, but
/// `AccountsViewModel.updateAccount` never sends it — an Account's opening
/// balance is immutable after creation
/// (`docs/adr/0007-computed-balance-over-reconciliation.md`).
public struct AccountFormValues: Equatable, Sendable {
    public var name: String
    public var type: AccountType
    public var openingBalance: Double

    public init(name: String, type: AccountType, openingBalance: Double) {
        self.name = name
        self.type = type
        self.openingBalance = openingBalance
    }
}
