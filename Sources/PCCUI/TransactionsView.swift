import SwiftUI

/// Minimal Mac/iOS screen for ticket #37: lists Transactions, and supports
/// creating, editing, and deleting one — each logged against exactly one
/// Account. One shared SwiftUI view for both platforms — no
/// platform-specific chrome, per this codebase's existing "minimal" scope
/// (mirrors `AccountsView`).
///
/// On the shared Liquid Glass system since issue #67 — full-width
/// `GlassBubble` rows on `GlassScreenBackground()`, one per Transaction,
/// replacing the earlier receipt-tape costume (torn-paper day cards,
/// perforation lines) `git log` on this file still shows.
public struct TransactionsView: View {
    @ObservedObject private var viewModel: TransactionsViewModel
    @State private var isPresentingNewTransactionSheet = false
    @State private var editingTransaction: Transaction?

    public init(viewModel: TransactionsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        TransactionsContent(
            viewModel: viewModel,
            isPresentingNewTransactionSheet: $isPresentingNewTransactionSheet,
            editingTransaction: $editingTransaction
        )
        .screenTheme(.liquidGlass)
    }
}

/// The screen's actual content — split out from `TransactionsView` itself
/// so `.screenTheme(.liquidGlass)` (applied in that struct's body, above)
/// is genuinely in effect by the time this struct's own `body` reads
/// `@Environment(\.screenTheme)`. See `View.screenTheme(_:)`'s doc comment
/// in `PCCChassis.swift` for why the split is required.
private struct TransactionsContent: View {
    @ObservedObject var viewModel: TransactionsViewModel
    @Binding var isPresentingNewTransactionSheet: Bool
    @Binding var editingTransaction: Transaction?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.transactions.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    transactionScroll
                }
            }
            .background(GlassScreenBackground())
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

    /// A `ScrollView` of `TransactionBubble`s, most-recent-first — each row
    /// draws the shared `GlassBubble` surface (mirrors `AccountsView`'s own
    /// move from `List` to `ScrollView` + custom cards for the same reason).
    /// Replaces the prior per-day `ReceiptCard` grouping: with no receipt
    /// costume left to hang a day boundary off of, every row just states its
    /// own full date, matching the flat "list of a label plus a figure"
    /// shape issue #67 asks for.
    private var transactionScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                statusStrip
                VStack(spacing: 18) {
                    ForEach(sortedTransactions) { transaction in
                        TransactionBubble(
                            transaction: transaction,
                            accountName: accountName(for: transaction),
                            tagLabel: tagLabel(for: transaction),
                            onTap: { editingTransaction = transaction }
                        )
                    }
                }
                .padding(.top, 18)
            }
            .padding(PCCChassis.outerMargin)
        }
    }

    /// `viewModel.transactions`, most-recent first — the flat ordering
    /// `transactionScroll` renders, now that there's no per-day grouping to
    /// sort within (`TransactionsViewModel.groupedByDay`'s replacement).
    private var sortedTransactions: [Transaction] {
        viewModel.transactions.sorted { $0.date > $1.date }
    }

    /// The name of whichever Account `transaction` is logged against,
    /// looked up from the view model's already-loaded picker data — falls
    /// back to a placeholder rather than crashing if the referenced Account
    /// isn't in the loaded list (e.g. deleted between loads), mirroring
    /// `WorkViewModel.containerLabel`.
    private func accountName(for transaction: Transaction) -> String {
        viewModel.accounts.first { $0.id == transaction.accountID }?.name ?? "Unknown Account"
    }

    /// "Category", "Category ▸ Subcategory", or `nil` if untagged.
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

    // MARK: - Status strip

    private var statusStrip: some View {
        HStack(spacing: 10) {
            StatusDot(overallStatus)
            Text(statusStripText)
                .pccPanelLabel()
                .foregroundStyle(.secondary)
            Spacer()
            Text(Self.formattedNet(netTotal))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(netTotal < 0 ? theme.signalRed(colorScheme) : theme.signalGreen(colorScheme))
        }
        .padding(.bottom, 12)
        .overlay(
            Rectangle()
                .fill(theme.panelLine(colorScheme))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private var netTotal: Double {
        viewModel.transactions.reduce(0) { $0 + ($1.type == .expense ? -$1.amount : $1.amount) }
    }

    private var overallStatus: PanelStatus {
        netTotal < 0 ? .critical : .nominal
    }

    private var statusStripText: String {
        let count = viewModel.transactions.count
        let noun = count == 1 ? "TRANSACTION" : "TRANSACTIONS"
        return "\(count) \(noun)"
    }

    private static func formattedNet(_ amount: Double) -> String {
        amount.formatted(.currency(code: "PHP").sign(strategy: .always()))
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
}

/// Shared create/edit form: the same sheet serves "New Transaction" and
/// "Edit Transaction" — an amount, a type picker, a date, optional notes, an
/// Account picker, and an optional Category/Subcategory pair of pickers
/// (ticket #39). Save stays disabled until an Account is picked — mirrors
/// `TimeEntryFormSheet`'s "exactly one container" gate, narrowed to
/// Transaction's single required container; the Category/Subcategory
/// pickers have no such gate, since "untagged" is a valid, ordinary state.
/// Its Sections stay in the shared chassis look — a `Form`'s native controls
/// don't read as glass however they're dressed (`AccountFormSheet`'s doc
/// comment carries this reasoning in full) — but its ground now repaints to
/// `GlassScreenBackground()` via `glassScreenBackground()`, per issue #67.
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
                    DatePicker("Date", selection: $date)
                    TextField("Notes", text: $notes)
                        .pccField()
                }
                .panelRows()
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
                .panelRows()
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

// MARK: - Transaction bubble

/// One Transaction row: the shared `GlassBubble` surface (`.fullWidth` size)
/// with this screen's own content on it — the Account it's logged against,
/// its date/tag/notes as a secondary label, and the signed amount as the
/// loud hero figure, colored red/green by expense/income the same
/// "read the color, not just the number" language `AccountBubble` uses for
/// balance sign. The bubble's material, tint, specular highlight and rim
/// come from `PCCChassis`, not from here; only the layout and the amount's
/// coloring are this screen's.
private struct TransactionBubble: View {
    let transaction: Transaction
    let accountName: String
    let tagLabel: String?
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    private static let style: GlassBubbleStyle = .fullWidth

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(accountName)
                        .font(.system(size: 16, weight: .semibold))
                    Text(metaText)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    if let notes = transaction.notes {
                        Text("\u{201C}\(notes)\u{201D}")
                            .font(.system(size: 11.5))
                            .italic()
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Text(Self.formattedAmount(transaction))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(amountColor)
                    .shadow(color: amountColor.opacity(colorScheme == .dark ? 0.5 : 0.28), radius: 10)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .glassBubble(Self.style)
            .contentShape(RoundedRectangle(cornerRadius: Self.style.cornerRadius, style: .continuous))
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
    }

    /// "Sep 2, 9:03 AM · Salary ▸ Monthly" — the full date now that there's
    /// no day-grouping header stating it once for every row underneath, per
    /// `TransactionRow`'s prior (day-relative) `metaText`.
    private var metaText: String {
        let dateTime = Self.dateTimeFormatter.string(from: transaction.date)
        guard let tagLabel else { return dateTime }
        return "\(dateTime) · \(tagLabel)"
    }

    private var amountColor: Color {
        transaction.type == .expense ? theme.signalRed(colorScheme) : theme.signalGreen(colorScheme)
    }

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter
    }()

    private static func formattedAmount(_ transaction: Transaction) -> String {
        let signed = transaction.type == .expense ? -transaction.amount : transaction.amount
        return signed.formatted(.currency(code: "PHP").sign(strategy: .always()))
    }
}
