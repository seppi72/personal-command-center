import SwiftUI

/// Minimal Mac/iOS screen for ticket #36: lists Accounts, and supports
/// creating, editing (name/type only), and deleting one. One shared
/// SwiftUI view for both platforms — no platform-specific chrome, per the
/// ticket's "minimal" scope (mirrors `ClientsView`).
public struct AccountsView: View {
    @ObservedObject private var viewModel: AccountsViewModel
    @State private var isPresentingNewAccountSheet = false
    @State private var editingAccount: Account?

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

    private var accountList: some View {
        List {
            ForEach(viewModel.accounts) { account in
                Button {
                    editingAccount = account
                } label: {
                    VStack(alignment: .leading) {
                        Text(account.name)
                        Text("\(account.type.displayName) · \(Self.formattedBalance(account.balance))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
        .glassScreenBackground()
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
