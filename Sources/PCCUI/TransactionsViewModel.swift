import Foundation

/// Holds the Transactions screen's state and talks to the backend through a
/// `TransactionsAPIClient`, plus an `AccountsAPIClient` to populate the
/// Account picker — kept separate from `TransactionsView` so the view stays
/// a thin rendering of this state (mirrors `TimeEntriesViewModel`'s split,
/// narrowed to Transaction's single picker source).
///
/// `ObservableObject` rather than the newer `@Observable` macro, since that
/// macro needs iOS 17/macOS 14 and this package targets iOS 16/macOS 13.
@MainActor
public final class TransactionsViewModel: ObservableObject {
    @Published public private(set) var transactions: [Transaction] = []
    @Published public private(set) var accounts: [Account] = []
    @Published public var errorMessage: String?
    @Published public private(set) var isLoading = false

    private let transactionsClient: TransactionsAPIClient
    private let accountsClient: AccountsAPIClient

    public init(transactionsClient: TransactionsAPIClient, accountsClient: AccountsAPIClient) {
        self.transactionsClient = transactionsClient
        self.accountsClient = accountsClient
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        await run(verb: "load") {
            async let loadedTransactions = transactionsClient.listTransactions(accountID: nil, start: nil, end: nil)
            async let loadedAccounts = accountsClient.listAccounts()
            transactions = try await loadedTransactions
            accounts = try await loadedAccounts
        }
    }

    public func createTransaction(_ values: TransactionFormValues) async {
        await run(verb: "create") {
            transactions.append(try await transactionsClient.createTransaction(values))
        }
    }

    public func updateTransaction(_ transaction: Transaction, with values: TransactionFormValues) async {
        await run(verb: "update") {
            let updated = try await transactionsClient.updateTransaction(id: transaction.id, values: values)
            if let index = transactions.firstIndex(where: { $0.id == updated.id }) {
                transactions[index] = updated
            }
        }
    }

    public func deleteTransaction(_ transaction: Transaction) async {
        await run(verb: "delete") {
            try await transactionsClient.deleteTransaction(id: transaction.id)
            transactions.removeAll { $0.id == transaction.id }
        }
    }

    /// Runs a mutation against `transactions`, keeping every method's
    /// success/failure handling (clear the error; on failure surface a
    /// message) in one shape instead of four copies (mirrors
    /// `TimeEntriesViewModel.run`).
    private func run(verb: String, _ operation: () async throws -> Void) async {
        do {
            try await operation()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't \(verb) Transaction: \(error.localizedDescription)"
        }
    }
}
