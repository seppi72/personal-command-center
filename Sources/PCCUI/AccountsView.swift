import SwiftUI

/// Minimal Mac/iOS screen for ticket #36: lists Accounts, and supports
/// creating, editing (name/type only), and deleting one. One shared
/// SwiftUI view for both platforms — no platform-specific chrome, per the
/// ticket's "minimal" scope (mirrors `CategoriesView`).
///
/// A status strip above the list (mirrors `OverviewView`'s own) gives the
/// account count and a `StatusDot` — `.critical` when any asset Account has
/// gone negative — before a single row is read; each row's balance is
/// this screen's own loud, confident hero number, colored green/red by
/// sign, the same "read the color, not just the number" language
/// `OverviewView`'s gauges use.
public struct AccountsView: View {
    @ObservedObject private var viewModel: AccountsViewModel

    public init(viewModel: AccountsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        AccountsContent(viewModel: viewModel)
            .screenTheme(.liquidGlass)
    }
}

/// The screen's actual content — split out from `AccountsView` itself so
/// `.screenTheme(.liquidGlass)` (applied in that struct's body, above) is
/// genuinely in effect by the time this struct's own `body` reads
/// `@Environment(\.screenTheme)`. See `View.screenTheme(_:)`'s doc comment
/// in `PCCChassis.swift` for why the split is required.
private struct AccountsContent: View {
    @ObservedObject var viewModel: AccountsViewModel
    @State private var isPresentingNewAccountSheet = false
    @State private var editingAccount: Account?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.accounts.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    accountScroll
                }
            }
            .background(GlassScreenBackground())
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
        .padding(.bottom, 12)
        .overlay(
            Rectangle()
                .fill(theme.panelLine(colorScheme))
                .frame(height: 1),
            alignment: .bottom
        )
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

    /// A `ScrollView` of `AccountBubble`s rather than a `List` — this
    /// screen's whole point is liquid glass floating on plain white/black,
    /// which needs each row to draw its own translucent Material-backed
    /// shape (the shared `GlassBubble`) rather than the console
    /// chassis's opaque `panelRows()` card fill (mirrors `CategoriesView`'s
    /// own move from `List` to `ScrollView` + custom cards for the same
    /// reason).
    private var accountScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                statusStrip
                VStack(spacing: 18) {
                    ForEach(viewModel.accounts) { account in
                        AccountBubble(
                            account: account,
                            onTap: { editingAccount = account },
                            onDelete: { Task { await viewModel.deleteAccount(account) } }
                        )
                    }
                }
                .padding(.top, 18)
            }
            .padding(PCCChassis.outerMargin)
        }
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
}

/// Shared create/edit form: the same sheet serves "New Account" and "Edit
/// Account" — name, a Type picker, and (create only) an opening balance
/// field. `isCreating` is what actually withholds the opening-balance
/// field on edit, not merely disables it — matching
/// `UpdateAccountRequest`'s own shape, which has no field for it at all
/// (`docs/adr/0007-computed-balance-over-reconciliation.md`). Left in the
/// shared chassis look rather than a bespoke glass re-theme — a `Form`'s
/// native controls (`Picker`, `TextField`) don't read as "liquid glass"
/// however they're dressed, so there's nothing this screen's own device
/// would add here.
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
                .panelRows()
                if !isCreating {
                    Section {
                        Text(openingBalanceText)
                            .foregroundStyle(.secondary)
                    } footer: {
                        Text("Opening balance can't be changed after an Account is created.")
                    }
                    .panelRows()
                }
            }
            .panelScreenBackground()
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

// MARK: - Account bubble

/// One account row: the shared `GlassBubble` surface (`.fullWidth` size) with
/// this screen's own content on it — a glass type-icon well, the account's
/// name and type, and the balance as the loud hero figure. The bubble's
/// material, tint, specular highlight and rim come from `PCCChassis`, not
/// from here; only the layout and the balance's coloring are this screen's.
private struct AccountBubble: View {
    let account: Account
    let onTap: () -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    private static let style: GlassBubbleStyle = .fullWidth

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                iconBubble
                VStack(alignment: .leading, spacing: 3) {
                    Text(account.name)
                        .font(.system(size: 16, weight: .semibold))
                    Text(account.type.displayName)
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .tracking(1.0)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(Self.formattedBalance(account.balance))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(balanceColor)
                    .shadow(color: balanceColor.opacity(colorScheme == .dark ? 0.5 : 0.28), radius: 10)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .glassBubble(Self.style)
            .contentShape(RoundedRectangle(cornerRadius: Self.style.cornerRadius, style: .continuous))
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// The type icon's own little glass well — cut from the same glass as
    /// the bubble behind it (`GlassBubble`'s own tint and rim), just round
    /// instead of a rounded rectangle, which is why it isn't a
    /// `GlassBubble` itself.
    private var iconBubble: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay(
                Circle().fill(GlassBubble.tint(for: colorScheme))
            )
            .overlay(
                Circle().strokeBorder(
                    GlassBubble.rimColor(theme, colorScheme), lineWidth: GlassBubble.rimWidth
                )
            )
            .frame(width: 46, height: 46)
            .overlay(
                Image(systemName: Self.systemImage(for: account.type))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.78))
            )
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

    private var balanceColor: Color {
        account.balance < 0 ? theme.signalRed(colorScheme) : theme.signalGreen(colorScheme)
    }

    private static func formattedBalance(_ balance: Double) -> String {
        balance.formatted(.currency(code: "PHP"))
    }
}
