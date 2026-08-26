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
                    accounts: viewModel.accounts
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
                        notes: transaction.notes
                    ),
                    accounts: viewModel.accounts
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
        }
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

    private static func formattedAmount(_ transaction: Transaction) -> String {
        let signed = transaction.type == .expense ? -transaction.amount : transaction.amount
        return signed.formatted(.currency(code: "USD").sign(strategy: .always()))
    }
}

/// Shared create/edit form: the same sheet serves "New Transaction" and
/// "Edit Transaction" — an amount, a type picker, a date, optional notes,
/// and an Account picker. Save stays disabled until an Account is picked —
/// mirrors `TimeEntryFormSheet`'s "exactly one container" gate, narrowed to
/// Transaction's single required container.
struct TransactionFormSheet: View {
    let title: String
    let accounts: [Account]
    let onSave: (TransactionFormValues) async -> Void

    @State private var accountID: UUID?
    @State private var amountText: String
    @State private var type: TransactionType
    @State private var date: Date
    @State private var notes: String
    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        initialValues: TransactionFormValues,
        accounts: [Account],
        onSave: @escaping (TransactionFormValues) async -> Void
    ) {
        self.title = title
        self.accounts = accounts
        self.onSave = onSave
        self._accountID = State(initialValue: initialValues.accountID)
        self._amountText = State(initialValue: initialValues.amount == 0 ? "" : String(initialValues.amount))
        self._type = State(initialValue: initialValues.type)
        self._date = State(initialValue: initialValues.date)
        self._notes = State(initialValue: initialValues.notes ?? "")
    }

    private var trimmedNotes: String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var amount: Double? {
        Double(amountText)
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
                Picker("Account", selection: $accountID) {
                    Text("Choose an Account").tag(UUID?.none)
                    ForEach(accounts) { account in
                        Text(account.name).tag(UUID?.some(account.id))
                    }
                }
                #if os(iOS)
                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)
                #else
                TextField("Amount", text: $amountText)
                #endif
                Picker("Type", selection: $type) {
                    ForEach(TransactionType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("Notes", text: $notes)
            }
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
                            notes: trimmedNotes
                        )
                        Task {
                            await onSave(values)
                            dismiss()
                        }
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}
