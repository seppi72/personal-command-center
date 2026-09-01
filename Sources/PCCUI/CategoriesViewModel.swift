import Foundation

/// Holds the Categories screen's state and talks to the backend through a
/// `CategoriesAPIClient`. Kept separate from `CategoriesView` so the view
/// stays a thin rendering of this state (mirrors `ClientsViewModel`'s split).
///
/// `ObservableObject` rather than the newer `@Observable` macro, since that
/// macro needs iOS 17/macOS 14 and this package targets iOS 16/macOS 13.
@MainActor
public final class CategoriesViewModel: ObservableObject {
    @Published public private(set) var categories: [PCCCategory] = []
    /// Every Transaction, loaded alongside `categories` — the "Category
    /// Glass" screen shows each Category's own Spent/Received total and
    /// biggest entries directly on its card (`spending`), so this view
    /// model needs Transaction data it previously had no reason to hold
    /// (mirrors `ClientsViewModel`'s own addition of Project data for the
    /// same kind of card).
    @Published public private(set) var transactions: [Transaction] = []
    @Published public var errorMessage: String?
    @Published public private(set) var isLoading = false

    private let client: CategoriesAPIClient
    private let subcategoriesClient: SubcategoriesAPIClient
    private let transactionsClient: TransactionsAPIClient

    public init(
        client: CategoriesAPIClient, subcategoriesClient: SubcategoriesAPIClient,
        transactionsClient: TransactionsAPIClient
    ) {
        self.client = client
        self.subcategoriesClient = subcategoriesClient
        self.transactionsClient = transactionsClient
    }

    /// Builds the `SubcategoriesViewModel` for one Category's detail screen,
    /// scoped to that Category's id — `CategoryDetailView` needs a
    /// `SubcategoriesAPIClient` and a `categoryID`, and this is where both
    /// are available together (mirrors `ProjectsViewModel.makeSprintsViewModel`).
    public func makeSubcategoriesViewModel(for category: PCCCategory) -> SubcategoriesViewModel {
        SubcategoriesViewModel(client: subcategoriesClient, categoryID: category.id)
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        await run(verb: "load") {
            async let loadedCategories = client.listCategories()
            async let loadedTransactions = transactionsClient.listTransactions(
                accountID: nil, start: nil, end: nil
            )
            categories = try await loadedCategories
            transactions = try await loadedTransactions
        }
    }

    /// Every Category's own `CategorySpending`, sorted by its headline
    /// total descending (most-spent/most-received first) — the Category
    /// Glass screen's own reason for existing: a glanceable "where did
    /// the money go" rather than a bare list of names.
    public var expenseCategories: [CategorySpending] {
        spendingByCategory.filter { !$0.isIncome }
    }

    public var incomeCategories: [CategorySpending] {
        spendingByCategory.filter { $0.isIncome }
    }

    private var spendingByCategory: [CategorySpending] {
        categories
            .map { category in
                let categoryTransactions = transactions.filter { $0.categoryID == category.id }
                let expenseTotal = categoryTransactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
                let incomeTotal = categoryTransactions.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
                return CategorySpending(
                    category: category, expenseTotal: expenseTotal, incomeTotal: incomeTotal,
                    transactions: categoryTransactions
                )
            }
            .sorted { $0.headlineTotal > $1.headlineTotal }
    }

    public func createCategory(name: String) async {
        await run(verb: "create") {
            categories.append(try await client.createCategory(name: name))
        }
    }

    public func updateCategory(_ existing: PCCCategory, name: String) async {
        await run(verb: "update") {
            let updated = try await client.updateCategory(id: existing.id, name: name)
            if let index = categories.firstIndex(where: { $0.id == updated.id }) {
                categories[index] = updated
            }
        }
    }

    public func deleteCategory(_ existing: PCCCategory) async {
        await run(verb: "delete") {
            try await client.deleteCategory(id: existing.id)
            categories.removeAll { $0.id == existing.id }
        }
    }

    /// Runs a mutation against `categories`, keeping every method's
    /// success/failure handling (clear the error, re-sort by name; on
    /// failure surface a message) in one shape instead of four copies
    /// (mirrors `ClientsViewModel.run`).
    private func run(verb: String, _ operation: () async throws -> Void) async {
        do {
            try await operation()
            categories.sort { $0.name < $1.name }
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't \(verb) Category: \(error.localizedDescription)"
        }
    }
}

/// One Category's spending picture, bucketed together by
/// `CategoriesViewModel.expenseCategories`/`incomeCategories` — a Category
/// isn't itself typed expense-vs-income (`CONTEXT.md` calls it just "a
/// label for grouping Transactions by kind of spending"), so which section
/// a Category lands in is inferred from its own Transactions rather than
/// stored on the Category itself.
public struct CategorySpending: Identifiable, Equatable {
    public let category: PCCCategory
    public let expenseTotal: Double
    public let incomeTotal: Double
    /// Every Transaction tagged with this Category, of either type — the
    /// raw material `topTransactions(limit:)` filters down to whichever
    /// type this Category is actually classified as.
    public let transactions: [Transaction]

    public var id: UUID { category.id }

    /// A Category counts as "Income" once its income total outweighs its
    /// expense total — including the untouched 0/0 case, which falls to
    /// Expense by default, matching this app's own framing of Categories
    /// as primarily an expense-organizing device.
    public var isIncome: Bool { incomeTotal > expenseTotal }

    public var headlineTotal: Double { isIncome ? incomeTotal : expenseTotal }

    /// This Category's own biggest entries, by magnitude — restricted to
    /// whichever type (`isIncome`) the Category is actually classified as,
    /// so a Category with a handful of small expenses and one large income
    /// entry doesn't show that income line under its Expense card.
    public func topTransactions(limit: Int) -> [Transaction] {
        let matchingType: TransactionType = isIncome ? .income : .expense
        return transactions
            .filter { $0.type == matchingType }
            .sorted { $0.amount > $1.amount }
            .prefix(limit)
            .map { $0 }
    }
}
