import SwiftUI

/// Minimal Mac/iOS screen for ticket #36: lists Accounts, and supports
/// creating, editing (name/type only), and deleting one. One shared
/// SwiftUI view for both platforms — no platform-specific chrome, per the
/// ticket's "minimal" scope (mirrors `ClientsView`).
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
            .background(DotGridBackground())
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
    /// shape (`AccountBubble.bubbleBackground`) rather than the shared
    /// chassis's opaque `panelRows()` card fill (mirrors `ClientsView`'s
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

// MARK: - Liquid Glass theme

extension ScreenTheme {
    /// `AccountsView`'s own vibe: real liquid glass — not the flat frosted-
    /// rectangle "glassmorphism" cliché — floating on plain white/black
    /// with no color in the background at all, per direct product
    /// feedback through two revisions (an original vault/safe-deposit
    /// direction, then a colorful refractive-mesh glass direction, both
    /// replaced by this one). `panelSurface`/`panelLine` only really
    /// surface in `AccountFormSheet`'s standard chassis look — the glass
    /// bubbles draw their own Material-backed fill
    /// (`AccountBubble.bubbleBackground`) rather than reading these.
    /// `signalGreen`/`signalRed` are overridden (unlike most other
    /// screens, which leave them as `ScreenTheme.default`'s) since the
    /// balance figure's color *is* this screen's signature accent, not an
    /// incidental status flag.
    fileprivate static let liquidGlass = ScreenTheme(
        panelVoid: { $0 == .dark ? Color.black : Color.white },
        panelSurface: { $0 == .dark ? Color(hex: 0x121212) : Color(hex: 0xF7F7F7) },
        panelLine: { $0 == .dark ? Color(hex: 0x2A2A2A) : Color(hex: 0xE3E3E3) },
        accent: { $0 == .dark ? Color(hex: 0x45C989) : Color(hex: 0x157A4C) },
        signalGreen: { $0 == .dark ? Color(hex: 0x45C989) : Color(hex: 0x157A4C) },
        signalAmber: ScreenTheme.default.signalAmber,
        signalRed: { $0 == .dark ? Color(hex: 0xE8695A) : Color(hex: 0xB23226) }
    )
}

// MARK: - Dot grid background

/// A hairline dot grid, almost invisible — enough for a glass bubble's
/// Material blur to have some texture to work with, without reading as a
/// "background" the way a colored gradient mesh would (the direction this
/// replaced, per feedback). Canvas-drawn rather than a repeating SwiftUI
/// view for the same performance reason `ProjectsView`'s
/// `DraftingGridBackground` draws its own grid lines this way.
private struct DotGridBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    private static let spacing: CGFloat = 22

    var body: some View {
        Canvas { context, size in
            let dotColor = theme.panelLine(colorScheme).opacity(0.8)
            var x: CGFloat = Self.spacing / 2
            while x < size.width {
                var y: CGFloat = Self.spacing / 2
                while y < size.height {
                    context.fill(
                        Path(ellipseIn: CGRect(x: x - 0.5, y: y - 0.5, width: 1, height: 1)),
                        with: .color(dotColor)
                    )
                    y += Self.spacing
                }
                x += Self.spacing
            }
        }
        .background(theme.panelVoid(colorScheme))
    }
}

// MARK: - Account bubble

/// This screen's signature: a real liquid-glass bubble — a `Material`-
/// backed shape (genuine OS-level backdrop blur/vibrancy, not a hand-rolled
/// approximation) with a soft tint gradient, a blurred specular highlight
/// arcing across the top like light catching a curved surface, and a
/// hairline rim — in place of the shared chassis's opaque bordered
/// `panelRows()` card every other List-backed screen uses.
private struct AccountBubble: View {
    let account: Account
    let onTap: () -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    private static let cornerRadius: CGFloat = 30

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
            .background(bubbleBackground)
            .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
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

    // MARK: Glass

    /// White-based regardless of theme — like real glass, the tint comes
    /// from what's behind it (here, the `Material`'s own light/dark
    /// vibrancy), not from the app's palette.
    private var glassFillTop: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.72)
    }

    private var glassFillBottom: Color {
        colorScheme == .dark ? Color.white.opacity(0.02) : Color.white.opacity(0.24)
    }

    private var bubbleBackground: some View {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .fill(LinearGradient(colors: [glassFillTop, glassFillBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(specularHighlight)
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .strokeBorder(theme.panelLine(colorScheme).opacity(0.7), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.08), radius: 20, x: 0, y: 10)
    }

    private var specularHighlight: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [.white.opacity(colorScheme == .dark ? 0.22 : 0.55), .clear],
                    center: .center, startRadius: 0, endRadius: 90
                )
            )
            .frame(width: 170, height: 90)
            .rotationEffect(.degrees(-12))
            .offset(x: -60, y: -46)
            .blur(radius: 10)
            .allowsHitTesting(false)
    }

    private var iconBubble: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay(
                Circle().fill(LinearGradient(colors: [glassFillTop, glassFillBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(
                Circle().strokeBorder(theme.panelLine(colorScheme).opacity(0.7), lineWidth: 1)
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
