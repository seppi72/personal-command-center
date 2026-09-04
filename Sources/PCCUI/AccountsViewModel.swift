import Foundation

/// Holds the Accounts screen's state and talks to the backend through an
/// `AccountsAPIClient`. Kept separate from `AccountsView` so the view stays
/// a thin rendering of this state (mirrors `WorkViewModel`'s split).
///
/// `ObservableObject` rather than the newer `@Observable` macro, since that
/// macro needs iOS 17/macOS 14 and this package targets iOS 16/macOS 13.
@MainActor
public final class AccountsViewModel: ObservableObject {
    @Published public private(set) var accounts: [Account] = []
    @Published public var errorMessage: String?
    @Published public private(set) var isLoading = false

    private let client: AccountsAPIClient

    public init(client: AccountsAPIClient) {
        self.client = client
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        await run(verb: "load") {
            accounts = try await client.listAccounts()
        }
    }

    public func createAccount(_ values: AccountFormValues) async {
        await run(verb: "create") {
            accounts.append(
                try await client.createAccount(
                    name: values.name, type: values.type, openingBalance: values.openingBalance
                )
            )
        }
    }

    /// Renames/retypes an Account — `values.openingBalance` is ignored here
    /// the same way `UpdateAccountRequest` has no field for it on the wire:
    /// an Account's opening balance is immutable after creation
    /// (`docs/adr/0007-computed-balance-over-reconciliation.md`).
    public func updateAccount(_ account: Account, with values: AccountFormValues) async {
        await run(verb: "update") {
            let updated = try await client.updateAccount(id: account.id, name: values.name, type: values.type)
            if let index = accounts.firstIndex(where: { $0.id == updated.id }) {
                accounts[index] = updated
            }
        }
    }

    public func deleteAccount(_ account: Account) async {
        await run(verb: "delete") {
            try await client.deleteAccount(id: account.id)
            accounts.removeAll { $0.id == account.id }
        }
    }

    /// Runs a mutation against `accounts`, keeping every method's
    /// success/failure handling (clear the error, re-sort by name; on
    /// failure surface a message) in one shape instead of four copies
    /// (mirrors `WorkViewModel.run`).
    private func run(verb: String, _ operation: () async throws -> Void) async {
        do {
            try await operation()
            accounts.sort { $0.name < $1.name }
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't \(verb) Account: \(error.localizedDescription)"
        }
    }
}
