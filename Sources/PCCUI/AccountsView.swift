import SwiftUI

/// Minimal Mac/iOS screen for ticket #36: lists Accounts, and supports
/// creating, editing (name/type only), and deleting one. One shared
/// SwiftUI view for both platforms — no platform-specific chrome, per the
/// ticket's "minimal" scope (mirrors `ClientsView`).
///
/// A status strip above the list (mirrors `OverviewView`'s own) gives the
/// account count and a `StatusDot` — `.critical` when any asset Account has
/// gone negative — before a single row is read; each row's balance is a
/// small monospaced readout colored green/red by sign, the same "read the
/// color, not just the number" language `OverviewView`'s gauges use.
public struct AccountsView: View {
    @ObservedObject private var viewModel: AccountsViewModel
    @State private var isPresentingNewAccountSheet = false
    @State private var editingAccount: Account?

    @Environment(\.colorScheme) private var colorScheme

    public init(viewModel: AccountsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            Group {
                if viewModel.accounts.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    accountList
                }
            }
            .navigationTitle("Accounts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingNewAccountSheet = true
                    } label: {
                        Label("Add Account", systemImage: "plus")
                    }
                }
            }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .alert("Error", isPresented: isShowingError, presenting: viewModel.errorMessage) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
            .sheet(isPresented: $isPresentingNewAccountSheet) {
                AccountFormSheet(
                    title: "New Account",
                    isCreating: true,
                    initialValues: AccountFormValues(name: "", type: .checking, openingBalance: 0)
                ) { values in
                    await viewModel.createAccount(values)
                }
            }
            .sheet(item: $editingAccount) { account in
                AccountFormSheet(
                    title: "Edit Account",
                    isCreating: false,
                    initialValues: AccountFormValues(
                        name: account.name, type: account.type, openingBalance: account.openingBalance
                    )
                ) { values in
                    await viewModel.updateAccount(account, with: values)
                }
            }
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
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .overlay(
            Rectangle()
                .fill(GlassStyle.panelLine(for: colorScheme))
                .frame(height: 1),
            alignment: .bottom
        )
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var overallStatus: PanelStatus {
        hasNegativeAsset ? .critical : .nominal
    }

    private var hasNegativeAsset: Bool {
        viewModel.accounts.contains { $0.classification == .asset && $0.balance < 0 }
    }

    private var statusStripText: String {
        let count = viewModel.accounts.count
        let noun = count == 1 ? "ACCOUNT" : "ACCOUNTS"
        let flagText = hasNegativeAsset ? "ASSET NEGATIVE" : "ALL NOMINAL"
        return "\(count) \(noun)   ·   \(flagText)"
    }

    // MARK: - List

    private var accountList: some View {
        List {
            Section {
                statusStrip
            }
            Section {
                ForEach(viewModel.accounts) { account in
                    Button {
                        editingAccount = account
                    } label: {
                        accountRow(account)
                    }
                    #if os(macOS)
                    .buttonStyle(.plain)
                    #endif
                }
                .onDelete { offsets in
                    let toDelete = offsets.map { viewModel.accounts[$0] }
                    Task {
                        for account in toDelete {
                            await viewModel.deleteAccount(account)
                        }
                    }
                }
                .glassRows()
            }
        }
        .glassScreenBackground()
    }

    private func accountRow(_ account: Account) -> some View {
        HStack(spacing: 12) {
            Image(systemName: Self.systemImage(for: account.type))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                Text(account.type.displayName)
                    .pccPanelLabel()
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Self.formattedBalance(account.balance))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Self.balanceColor(account.balance, for: colorScheme))
        }
    }

    private static func systemImage(for type: AccountType) -> String {
        switch type {
        case .checking: return "building.columns"
        case .savings: return "banknote"
        case .cash: return "dollarsign.circle"
        case .creditCard: return "creditcard"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .loan: return "arrow.down.circle"
        }
    }

    private static func balanceColor(_ balance: Double, for colorScheme: ColorScheme) -> Color {
        balance < 0 ? GlassStyle.signalRed(for: colorScheme) : GlassStyle.signalGreen(for: colorScheme)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No Accounts")
                .font(.headline)
            Text("Tap + to create your first Account.")
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

    private static func formattedBalance(_ balance: Double) -> String {
        balance.formatted(.currency(code: "PHP"))
    }
}

/// Shared create/edit form: the same sheet serves "New Account" and "Edit
/// Account" — name, a Type picker, and (create only) an opening balance
/// field. `isCreating` is what actually withholds the opening-balance
/// field on edit, not merely disables it — matching
/// `UpdateAccountRequest`'s own shape, which has no field for it at all
/// (`docs/adr/0007-computed-balance-over-reconciliation.md`).
struct AccountFormSheet: View {
    let title: String
    let isCreating: Bool
    let onSave: (AccountFormValues) async -> Void

    @State private var name: String
    @State private var type: AccountType
    @State private var openingBalanceText: String
    @Environment(\.dismiss) private var dismiss

    init(
        title: String, isCreating: Bool, initialValues: AccountFormValues,
        onSave: @escaping (AccountFormValues) async -> Void
    ) {
        self.title = title
        self.isCreating = isCreating
        self.onSave = onSave
        self._name = State(initialValue: initialValues.name)
        self._type = State(initialValue: initialValues.type)
        self._openingBalanceText = State(initialValue: String(initialValues.openingBalance))
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var openingBalance: Double? {
        Double(openingBalanceText)
    }

    private var isValid: Bool {
        !trimmedName.isEmpty && (!isCreating || openingBalance != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .pccField()
                    PCCMenuPicker("Type", selection: $type, options: AccountType.allCases.map { ($0, $0.displayName) })
                    if isCreating {
                        #if os(iOS)
                        TextField("Opening Balance", text: $openingBalanceText)
                            .keyboardType(.decimalPad)
                            .pccField()
                        #else
                        TextField("Opening Balance", text: $openingBalanceText)
                            .pccField()
                        #endif
                    }
                }
                .glassRows()
                if !isCreating {
                    Section {
                        Text(openingBalanceText)
                            .foregroundStyle(.secondary)
                    } footer: {
                        Text("Opening balance can't be changed after an Account is created.")
                    }
                    .glassRows()
                }
            }
            .glassScreenBackground()
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let values = AccountFormValues(
                            name: trimmedName, type: type, openingBalance: openingBalance ?? 0
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
