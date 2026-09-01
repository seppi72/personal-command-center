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
        TransactionsContent(
            viewModel: viewModel,
            isPresentingNewTransactionSheet: $isPresentingNewTransactionSheet,
            editingTransaction: $editingTransaction
        )
        .screenTheme(.receiptTape)
    }
}

/// The screen's actual content — split out from `TransactionsView` itself
/// so `.screenTheme(.receiptTape)` (applied in that struct's body, above)
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
                    receiptScroll
                }
            }
            .background(theme.panelVoid(colorScheme))
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

    /// A `ScrollView` of `ReceiptCard`s — one torn-off slip per day
    /// (`TransactionsViewModel.groupedByDay`) — rather than a `List`: each
    /// slip draws its own zigzag torn-paper silhouette
    /// (`TornPaperShape`), which a `List`'s opaque native row chrome can't
    /// host (mirrors `AccountsView`'s own move from `List` to `ScrollView`
    /// + custom cards for the same reason).
    private var receiptScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                statusStrip
                VStack(spacing: 26) {
                    ForEach(viewModel.groupedByDay) { group in
                        ReceiptCard(group: group, viewModel: viewModel, onTap: { editingTransaction = $0 })
                    }
                }
                .padding(.top, 20)
            }
            .padding(PCCChassis.outerMargin)
        }
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
/// Left in the shared chassis look rather than a bespoke receipt re-theme —
/// a `Form`'s native controls don't read as "printed on paper" however
/// they're dressed, so there's nothing this screen's own device would add
/// here (mirrors `AccountFormSheet`'s identical reasoning).
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
            .panelScreenBackground()
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

// MARK: - Receipt Tape theme

extension ScreenTheme {
    /// `TransactionsView`'s own vibe: a cash-register receipt — warm cream
    /// thermal-paper stock in Light Mode, a dim till-counter read of the
    /// same paper in Dark Mode (deep warm charcoal with pale "burned" ink,
    /// since thermal paper has no real dark-mode form of its own).
    /// `signalGreen`/`signalRed` are overridden (unlike most other screens,
    /// which leave them as `ScreenTheme.default`'s) toward print-ink hues
    /// rather than screen neon, since income/expense color is this
    /// screen's whole reason to use color at all.
    fileprivate static let receiptTape = ScreenTheme(
        panelVoid: { $0 == .dark ? Color(hex: 0x1B1812) : Color(hex: 0xF5F1E4) },
        panelSurface: { $0 == .dark ? Color(hex: 0x242019) : Color(hex: 0xFFFFFF) },
        panelLine: { $0 == .dark ? Color(hex: 0x3A342A) : Color(hex: 0xD8D2BE) },
        accent: { $0 == .dark ? Color(hex: 0xEDE6D6) : Color(hex: 0x2B2820) },
        signalGreen: { $0 == .dark ? Color(hex: 0x5FBF8B) : Color(hex: 0x1F6B44) },
        signalAmber: ScreenTheme.default.signalAmber,
        signalRed: { $0 == .dark ? Color(hex: 0xE2776A) : Color(hex: 0xA83226) }
    )
}

// MARK: - Torn paper shape

/// A rounded-rectangle-like silhouette with a zigzag torn edge along its
/// top and bottom instead of a straight one — one continuous subpath (a
/// single `moveTo` followed by `addLine`s and a `closeSubpath`), per
/// `View.screenTheme(_:)`'s own caution in `PCCChassis.swift` about
/// multi-subpath `Shape`s silently dropping a piece. Scales to whatever
/// frame it's given (`path(in rect:)`), so the tooth count adapts to each
/// day's card width rather than being fixed.
private struct TornPaperShape: Shape {
    var toothWidth: CGFloat = 14
    var toothHeight: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        let toothCount = max(2, Int((rect.width / toothWidth).rounded()))
        let actualToothWidth = rect.width / CGFloat(toothCount)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + toothHeight))

        // Top edge, left to right — alternates each tooth's peak between
        // the outer and inner edge.
        for tooth in 0..<toothCount {
            let xStart = rect.minX + CGFloat(tooth) * actualToothWidth
            let xMid = xStart + actualToothWidth / 2
            let xEnd = xStart + actualToothWidth
            let peakY = tooth.isMultiple(of: 2) ? rect.minY : rect.minY + toothHeight
            path.addLine(to: CGPoint(x: xMid, y: peakY))
            path.addLine(to: CGPoint(x: xEnd, y: rect.minY + toothHeight))
        }

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - toothHeight))

        // Bottom edge, right to left.
        for tooth in stride(from: toothCount - 1, through: 0, by: -1) {
            let xEnd = rect.minX + CGFloat(tooth) * actualToothWidth
            let xMid = xEnd + actualToothWidth / 2
            let xStart = xEnd + actualToothWidth
            let peakY = tooth.isMultiple(of: 2) ? rect.maxY : rect.maxY - toothHeight
            path.addLine(to: CGPoint(x: xStart, y: rect.maxY - toothHeight))
            path.addLine(to: CGPoint(x: xMid, y: peakY))
        }

        path.closeSubpath()
        return path
    }
}

// MARK: - Perforation

/// A single horizontal dashed rule standing in for the punched tear-line
/// between two Transactions logged on the same day. One continuous
/// subpath, same reasoning as `TornPaperShape`.
private struct PerforationLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

// MARK: - Receipt card

/// This screen's signature: one calendar day's Transactions as their own
/// separate torn-off slip of receipt tape — a `TornPaperShape` background,
/// a header carrying that day's date/count/net, and each Transaction
/// printed as a dot-matrix-style monospace line with a punched
/// `PerforationLine` between entries.
private struct ReceiptCard: View {
    let group: TransactionDayGroup
    /// Not `@ObservedObject` — `TransactionsContent` already observes this
    /// same instance and rebuilds `ReceiptCard` (via `ForEach`) whenever it
    /// publishes a change, so this card just needs a snapshot to resolve
    /// each row's Account/Category names against (mirrors `ClientCard`
    /// taking an already-resolved `projects: [Project]` rather than a
    /// whole view model).
    let viewModel: TransactionsViewModel
    let onTap: (Transaction) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dayHeader
            ForEach(Array(group.transactions.enumerated()), id: \.element.id) { index, transaction in
                if index > 0 {
                    PerforationLine()
                        .stroke(theme.panelLine(colorScheme), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .frame(height: 1)
                }
                TransactionRow(
                    transaction: transaction,
                    accountName: accountName(for: transaction),
                    tagLabel: tagLabel(for: transaction),
                    onTap: { onTap(transaction) }
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            TornPaperShape()
                .fill(theme.panelSurface(colorScheme))
                .overlay(TornPaperShape().stroke(theme.panelLine(colorScheme), lineWidth: 1))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.10), radius: 14, x: 0, y: 8)
        )
    }

    private var dayHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Self.dayFormatter.string(from: group.day))
                .font(.system(size: 12.5, weight: .heavy, design: .monospaced))
                .tracking(0.6)
                .textCase(.uppercase)
            Text(countText)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(Self.formattedNet(group.netAmount))
                .font(.system(size: 12.5, weight: .heavy, design: .monospaced))
                .foregroundStyle(group.netAmount < 0 ? theme.signalRed(colorScheme) : theme.signalGreen(colorScheme))
        }
        .padding(.bottom, 10)
    }

    private var countText: String {
        group.transactions.count == 1 ? "1 TRANSACTION" : "\(group.transactions.count) TRANSACTIONS"
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d, yyyy"
        return formatter
    }()

    private static func formattedNet(_ amount: Double) -> String {
        amount.formatted(.currency(code: "PHP").sign(strategy: .always()))
    }

    /// The name of whichever Account `transaction` is logged against,
    /// looked up from the view model's already-loaded picker data — falls
    /// back to a placeholder rather than crashing if the referenced Account
    /// isn't in the loaded list (e.g. deleted between loads), mirroring
    /// `TimeEntriesViewModel.containerLabel`.
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
}

private struct TransactionRow: View {
    let transaction: Transaction
    let accountName: String
    let tagLabel: String?
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(accountName)
                        .font(.system(size: 13.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(Self.formattedAmount(transaction))
                        .font(.system(size: 13.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(transaction.type == .expense ? theme.signalRed(colorScheme) : theme.signalGreen(colorScheme))
                }
                Text(metaText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                if let notes = transaction.notes {
                    Text("\u{201C}\(notes)\u{201D}")
                        .font(.system(size: 11, design: .monospaced))
                        .italic()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
    }

    /// "9:03 AM · Salary ▸ Monthly" — the transaction's time (its day
    /// already appears once, in `ReceiptCard.dayHeader`, not once per row)
    /// followed by its Category/Subcategory tag, if any.
    private var metaText: String {
        let time = Self.timeFormatter.string(from: transaction.date)
        guard let tagLabel else { return time }
        return "\(time) · \(tagLabel)"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private static func formattedAmount(_ transaction: Transaction) -> String {
        let signed = transaction.type == .expense ? -transaction.amount : transaction.amount
        return signed.formatted(.currency(code: "PHP").sign(strategy: .always()))
    }
}
