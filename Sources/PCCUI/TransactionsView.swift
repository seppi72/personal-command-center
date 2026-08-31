import SwiftUI

/// Minimal Mac/iOS screen for ticket #37: lists Transactions, and supports
/// creating, editing, and deleting one — each logged against exactly one
/// Account. One shared SwiftUI view for both platforms — no
/// platform-specific chrome, per this codebase's existing "minimal" scope
/// (mirrors `AccountsView`/`TimeEntriesView`).
public struct TransactionsView: View {
    @ObservedObject private var viewModel: TransactionsViewModel
    @State private var isPresentingNewTransactionSheet = false
    @State private var editingTransaction: Transaction?

    public init(viewModel: TransactionsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            Group {
                if viewModel.transactions.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    transactionList
                }
            }
            .navigationTitle("Transactions")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingNewTransactionSheet = true
                    } label: {
                        Label("Add Transaction", systemImage: "plus")
                    }
                    .disabled(viewModel.accounts.isEmpty)
                }
            }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .alert("Error", isPresented: isShowingError, presenting: viewModel.errorMessage) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
            .sheet(isPresented: $isPresentingNewTransactionSheet) {
                TransactionFormSheet(
                    title: "New Transaction",
                    initialValues: TransactionFormValues(amount: 0, type: .expense),
                    accounts: viewModel.accounts,
                    categories: viewModel.categories,
                    subcategories: { self.viewModel.subcategories(inCategory: $0) }
                ) { values in
                    await viewModel.createTransaction(values)
                }
            }
            .sheet(item: $editingTransaction) { transaction in
                TransactionFormSheet(
                    title: "Edit Transaction",
                    initialValues: TransactionFormValues(
                        accountID: transaction.accountID,
                        amount: transaction.amount,
                        type: transaction.type,
                        date: transaction.date,
                        notes: transaction.notes,
                        categoryID: transaction.categoryID,
                        subcategoryID: transaction.subcategoryID
                    ),
                    accounts: viewModel.accounts,
                    categories: viewModel.categories,
                    subcategories: { self.viewModel.subcategories(inCategory: $0) }
                ) { values in
                    await viewModel.updateTransaction(transaction, with: values)
                }
            }
        }
    }

    private var transactionList: some View {
        List {
            ForEach(viewModel.transactions.sorted { $0.date > $1.date }) { transaction in
                Button {
                    editingTransaction = transaction
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(accountName(for: transaction))
                            Spacer()
                            Text(Self.formattedAmount(transaction))
                                .foregroundStyle(transaction.type == .expense ? .red : .green)
                        }
                        Text(transaction.date, style: .date)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let tagLabel = tagLabel(for: transaction) {
                            Text(tagLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let notes = transaction.notes {
                            Text(notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                #if os(macOS)
                .buttonStyle(.plain)
                #endif
            }
            .onDelete { offsets in
                let sorted = viewModel.transactions.sorted { $0.date > $1.date }
                let toDelete = offsets.map { sorted[$0] }
                Task {
                    for transaction in toDelete {
                        await viewModel.deleteTransaction(transaction)
                    }
                }
            }
            .glassRows()
        }
        .glassScreenBackground()
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No Transactions")
                .font(.headline)
            Text(
                viewModel.accounts.isEmpty
                    ? "Create an Account first, then log your first Transaction."
                    : "Tap + to log your first Transaction."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isShowing in if !isShowing { viewModel.errorMessage = nil } }
        )
    }

    /// The name of whichever Account `transaction` is logged against,
    /// looked up from the view model's already-loaded picker data — falls
    /// back to a placeholder rather than crashing if the referenced Account
    /// isn't in the loaded list (e.g. deleted between loads), mirroring
    /// `TimeEntriesView.containerLabel`.
    private func accountName(for transaction: Transaction) -> String {
        viewModel.accounts.first { $0.id == transaction.accountID }?.name ?? "Unknown Account"
    }

    /// "Category", "Category ▸ Subcategory", or `nil` if untagged — the same
    /// "look up from already-loaded picker data" shape `accountName(for:)`
    /// already has (ticket #39).
    private func tagLabel(for transaction: Transaction) -> String? {
        guard let categoryID = transaction.categoryID,
              let categoryName = viewModel.categories.first(where: { $0.id == categoryID })?.name
        else {
            return nil
        }
        guard let subcategoryID = transaction.subcategoryID,
              let subcategoryName = viewModel.subcategories.first(where: { $0.id == subcategoryID })?.name
        else {
            return categoryName
        }
        return "\(categoryName) ▸ \(subcategoryName)"
    }

    private static func formattedAmount(_ transaction: Transaction) -> String {
        let signed = transaction.type == .expense ? -transaction.amount : transaction.amount
        return signed.formatted(.currency(code: "PHP").sign(strategy: .always()))
    }
}

/// Shared create/edit form: the same sheet serves "New Transaction" and
/// "Edit Transaction" — an amount, a type picker, a date, optional notes, an
/// Account picker, and an optional Category/Subcategory pair of pickers
/// (ticket #39). Save stays disabled until an Account is picked — mirrors
/// `TimeEntryFormSheet`'s "exactly one container" gate, narrowed to
/// Transaction's single required container; the Category/Subcategory
/// pickers have no such gate, since "untagged" is a valid, ordinary state.
struct TransactionFormSheet: View {
    let title: String
    let accounts: [Account]
    let categories: [PCCCategory]
    /// The Subcategories belonging to a given Category — looked up lazily
    /// rather than passed as one flat array, so this view stays agnostic of
    /// how `TransactionsViewModel` sources/caches them.
    let subcategoriesForCategory: (UUID) -> [Subcategory]
    let onSave: (TransactionFormValues) async -> Void

    @State private var accountID: UUID?
    @State private var amountText: String
    @State private var type: TransactionType
    @State private var date: Date
    @State private var notes: String
    @State private var categoryID: UUID?
    @State private var subcategoryID: UUID?
    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        initialValues: TransactionFormValues,
        accounts: [Account],
        categories: [PCCCategory],
        subcategories: @escaping (UUID) -> [Subcategory],
        onSave: @escaping (TransactionFormValues) async -> Void
    ) {
        self.title = title
        self.accounts = accounts
        self.categories = categories
        self.subcategoriesForCategory = subcategories
        self.onSave = onSave
        self._accountID = State(initialValue: initialValues.accountID)
        self._amountText = State(initialValue: initialValues.amount == 0 ? "" : String(initialValues.amount))
        self._type = State(initialValue: initialValues.type)
        self._date = State(initialValue: initialValues.date)
        self._notes = State(initialValue: initialValues.notes ?? "")
        self._categoryID = State(initialValue: initialValues.categoryID)
        self._subcategoryID = State(initialValue: initialValues.subcategoryID)
    }

    private var trimmedNotes: String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var amount: Double? {
        Double(amountText)
    }

    /// The current Category's Subcategories — empty (and so hides the
    /// Subcategory picker entirely) until a Category is chosen, mirroring
    /// the backend's own "a Subcategory requires its parent Category" rule
    /// (`TransactionController.verifyCategoryAndSubcategory`).
    private var availableSubcategories: [Subcategory] {
        guard let categoryID else { return [] }
        return subcategoriesForCategory(categoryID)
    }

    /// `amount` must be a positive magnitude — `type` carries the sign
    /// (`Transaction.signedAmount`) — matching
    /// `TransactionController.validatedAmount`'s own server-side check.
    private var isValid: Bool {
        accountID != nil && (amount ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PCCMenuPicker(
                        "Account", selection: $accountID,
                        options: accounts.map { (Optional($0.id), $0.name) },
                        placeholder: "Choose an Account"
                    )
                    #if os(iOS)
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                        .pccField()
                    #else
                    TextField("Amount", text: $amountText)
                        .pccField()
                    #endif
                    PCCMenuPicker("Type", selection: $type, options: TransactionType.allCases.map { ($0, $0.displayName) })
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Notes", text: $notes)
                        .pccField()
                }
                .glassRows()
                Section("Category") {
                    PCCMenuPicker(
                        "Category", selection: $categoryID,
                        options: [(UUID?.none, "None")] + categories.map { (Optional($0.id), $0.name) }
                    )
                    if categoryID != nil {
                        PCCMenuPicker(
                            "Subcategory", selection: $subcategoryID,
                            options: [(UUID?.none, "None")] + availableSubcategories.map { (Optional($0.id), $0.name) }
                        )
                    }
                }
                .glassRows()
            }
            .glassScreenBackground()
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let values = TransactionFormValues(
                            accountID: accountID,
                            amount: amount ?? 0,
                            type: type,
                            date: date,
                            notes: trimmedNotes,
                            categoryID: categoryID,
                            subcategoryID: subcategoryID
                        )
                        Task {
                            await onSave(values)
                            dismiss()
                        }
                    }
                    .disabled(!isValid)
                }
            }
            // Clearing the Category, or switching to one that doesn't
            // contain the currently-picked Subcategory, clears the
            // Subcategory too — the same "child cleared when it no longer
            // belongs to the new parent" shape `TaskController.assignProject`
            // already enforces server-side for a Task's Sprint.
            .onChange(of: categoryID) { newCategoryID in
                guard let newCategoryID else {
                    subcategoryID = nil
                    return
                }
                if let subcategoryID, !subcategoriesForCategory(newCategoryID).contains(where: { $0.id == subcategoryID }) {
                    self.subcategoryID = nil
                }
            }
        }
    }
}
