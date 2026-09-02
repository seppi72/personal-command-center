import Foundation

/// Holds the Transactions screen's state and talks to the backend through a
/// `TransactionsAPIClient`, plus an `AccountsAPIClient` to populate the
/// Account picker and a `CategoriesAPIClient`/`SubcategoriesAPIClient` pair
/// to populate the Category/Subcategory pickers (ticket #39) — kept separate
/// from `TransactionsView` so the view stays a thin rendering of this state
/// (mirrors `TimeEntriesViewModel`'s split).
///
/// `ObservableObject` rather than the newer `@Observable` macro, since that
/// macro needs iOS 17/macOS 14 and this package targets iOS 16/macOS 13.
@MainActor
public final class TransactionsViewModel: ObservableObject {
    @Published public private(set) var transactions: [Transaction] = []
    @Published public private(set) var accounts: [Account] = []
    @Published public private(set) var categories: [PCCCategory] = []
    @Published public private(set) var subcategories: [Subcategory] = []
    @Published public var errorMessage: String?
    @Published public private(set) var isLoading = false

    private let transactionsClient: TransactionsAPIClient
    private let accountsClient: AccountsAPIClient
    private let categoriesClient: CategoriesAPIClient
    private let subcategoriesClient: SubcategoriesAPIClient

    public init(
        transactionsClient: TransactionsAPIClient,
        accountsClient: AccountsAPIClient,
        categoriesClient: CategoriesAPIClient,
        subcategoriesClient: SubcategoriesAPIClient
    ) {
        self.transactionsClient = transactionsClient
        self.accountsClient = accountsClient
        self.categoriesClient = categoriesClient
        self.subcategoriesClient = subcategoriesClient
    }

    /// The Subcategories belonging to `categoryID` — what
    /// `TransactionFormSheet`'s Subcategory picker filters `subcategories`
    /// down to once a Category is chosen.
    public func subcategories(inCategory categoryID: UUID) -> [Subcategory] {
        subcategories.filter { $0.categoryID == categoryID }
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        await run(verb: "load") {
            async let loadedTransactions = transactionsClient.listTransactions(accountID: nil, start: nil, end: nil)
            async let loadedAccounts = accountsClient.listAccounts()
            async let loadedCategories = categoriesClient.listCategories()
            transactions = try await loadedTransactions
            accounts = try await loadedAccounts
            categories = try await loadedCategories
            // A Subcategory has no meaning outside its Category, so listing
            // it is always scoped to one (`SubcategoriesAPIClient`) — there's
            // no single "all Subcategories" call to make. Categories are a
            // small, owner-created list (unlike, say, Transactions), so
            // fetching each one's Subcategories here is one short round trip
            // per Category rather than a concern worth optimizing away.
            subcategories = try await Self.loadAllSubcategories(categories: categories, client: subcategoriesClient)
        }
    }

    private static func loadAllSubcategories(
        categories: [PCCCategory], client: SubcategoriesAPIClient
    ) async throws -> [Subcategory] {
        try await withThrowingTaskGroup(of: [Subcategory].self) { group in
            for category in categories {
                group.addTask { try await client.listSubcategories(categoryID: category.id) }
            }
            var all: [Subcategory] = []
            for try await batch in group {
                all.append(contentsOf: batch)
            }
            return all
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
