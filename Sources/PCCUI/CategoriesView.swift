import SwiftUI

/// Minimal Mac/iOS screen for ticket #39: lists Categories, and supports
/// creating, editing (renaming), and deleting one. One shared SwiftUI view
/// for both platforms — no platform-specific chrome, per this codebase's
/// existing "minimal" scope (mirrors `ProjectsView`). Tapping a card expands
/// it into a centered overlay showing its top 3 biggest entries
/// (`CategoriesContent.expandedOverlay(_:)`); reaching `CategoryDetailView`
/// to rename the Category or manage its Subcategories moved to a "Manage
/// Category" link inside that overlay, since a single tap is now spent on
/// the expand gesture instead.
public struct CategoriesView: View {
    @ObservedObject private var viewModel: CategoriesViewModel
    @State private var isPresentingNewCategorySheet = false

    public init(viewModel: CategoriesViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        CategoriesContent(viewModel: viewModel, isPresentingNewCategorySheet: $isPresentingNewCategorySheet)
            .screenTheme(.categoryGlass)
    }
}

/// The screen's actual content — split out from `CategoriesView` itself so
/// `.screenTheme(.categoryGlass)` (applied in that struct's body, above) is
/// genuinely in effect by the time this struct's own `body` reads
/// `@Environment(\.screenTheme)`. See `View.screenTheme(_:)`'s doc comment
/// in `PCCChassis.swift` for why the split is required.
private struct CategoriesContent: View {
    @ObservedObject var viewModel: CategoriesViewModel
    @Binding var isPresentingNewCategorySheet: Bool

    /// Which card (if any) is currently expanded — tapping a collapsed grid
    /// card sets this; tapping the scrim, the close button, or the same
    /// card again clears it. Drives `categoryScroll`'s `expandedOverlay(_:)`,
    /// a centered modal-style card rather than something grown in place
    /// from the source cell (see that method's own doc comment for why).
    @State private var expandedCategoryID: UUID?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.categories.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    categoryScroll
                }
            }
            .background(DotGridBackground())
            .navigationTitle("Categories")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingNewCategorySheet = true
                    } label: {
                        Label("Add Category", systemImage: "plus")
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
            .sheet(isPresented: $isPresentingNewCategorySheet) {
                CategoryFormSheet(title: "New Category", initialName: "") { name in
                    await viewModel.createCategory(name: name)
                }
            }
        }
    }

    /// A `ScrollView` of `CategoryCard`s in two `LazyVGrid` sections
    /// (Expense/Income) rather than a `List` — each card draws its own
    /// translucent Material-backed glass shape, neither of which a
    /// `List`'s opaque native row chrome can host (mirrors `AccountsView`'s
    /// own move from `List` to `ScrollView` + custom cards for the same
    /// reason).
    ///
    /// The expand device is a centered modal-style card, not something
    /// grown in place out of its source grid cell — two real bugs came out
    /// of the grown-in-place approach before this rewrite: `LazyVGrid`
    /// doesn't reliably honor `zIndex` across its own cells (a hovered,
    /// enlarged card kept rendering *behind* its neighbor even with
    /// `zIndex` set directly on the `LazyVGrid`'s own direct child — this
    /// screen's `git log` has the anchor-preference/`overlayPreferenceValue`
    /// workaround that was built for that), and anchoring the grown card to
    /// its source cell's own top-left corner never actually read as
    /// "growing" no matter how the transition's starting scale was tuned —
    /// it read as a pop-in at a slightly odd position instead. A card
    /// centered over a dimmed scrim sidesteps both: there's no sibling to
    /// stack above (the scrim + card sit in one `ZStack` slot, structurally
    /// on top of the whole grid already), and a plain `.scale`/`.opacity`
    /// transition centered on itself reads as intended without needing to
    /// match any other view's geometry.
    private var categoryScroll: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    statusStrip
                    if !viewModel.expenseCategories.isEmpty {
                        sectionLabel("Expense", count: viewModel.expenseCategories.count)
                        categoryGrid(viewModel.expenseCategories)
                    }
                    if !viewModel.incomeCategories.isEmpty {
                        sectionLabel("Income", count: viewModel.incomeCategories.count)
                        categoryGrid(viewModel.incomeCategories)
                    }
                }
                .padding(PCCChassis.outerMargin)
            }
            if let expandedCategoryID, let spending = spending(for: expandedCategoryID) {
                expandedOverlay(spending)
            }
        }
        // On the enclosing `ZStack`, not the conditional content itself, so
        // it governs the whole insert/remove transition below rather than
        // only in-place property changes.
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: expandedCategoryID)
    }

    /// The single floating, enlarged `CategoryCard` for whichever Category
    /// is tapped — a dimmed scrim behind it (tap to dismiss), a close
    /// button on the card itself, and a "Manage Category" link down to
    /// `CategoryDetailView` now that a tap on the collapsed card spends
    /// itself on expanding rather than navigating.
    private func expandedOverlay(_ spending: CategorySpending) -> some View {
        ZStack {
            // Its own opacity-only transition — kept separate from the
            // card's `.scale` transition below. A single `.transition` on
            // the enclosing `ZStack` would apply to every descendant,
            // including this full-screen scrim, which is what made the
            // dimmed background itself visibly scale in from 92% alongside
            // the card instead of just fading.
            Rectangle()
                .fill(scrimColor)
                .ignoresSafeArea()
                .onTapGesture { expandedCategoryID = nil }
                .transition(.opacity)
            VStack(spacing: 14) {
                CategoryCard(spending: spending, isExpanded: true)
                    .background(bubbleShadow)
                    .overlay(alignment: .topTrailing) {
                        Button {
                            expandedCategoryID = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(10)
                    }
                NavigationLink {
                    CategoryDetailView(
                        category: spending.category,
                        viewModel: viewModel,
                        subcategoriesViewModel: viewModel.makeSubcategoriesViewModel(for: spending.category)
                    )
                } label: {
                    Label("Manage Category", systemImage: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                }
                #if os(macOS)
                .buttonStyle(.plain)
                #endif
                .foregroundStyle(theme.accent(colorScheme))
            }
            .frame(maxWidth: 360)
            // Distinct identity per Category so switching which card is
            // expanded is a genuine remove-then-insert (each transitioning
            // on its own) rather than one view's content silently
            // swapping. Only this card scales in/out — the scrim above
            // just fades.
            .id(spending.id)
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
        }
        .zIndex(1)
    }

    private var scrimColor: Color {
        Color.black.opacity(colorScheme == .dark ? 0.6 : 0.28)
    }

    /// A drop shadow behind the expanded card — kept out of
    /// `CategoryCard.bubbleBackground` itself (which the collapsed grid
    /// cells also use) since only the enlarged overlay instance needs the
    /// heavier "lifted toward the viewer" shadow.
    private var bubbleShadow: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(Color.clear)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.55 : 0.16), radius: 26, x: 0, y: 14)
    }

    private func spending(for id: UUID) -> CategorySpending? {
        (viewModel.expenseCategories + viewModel.incomeCategories).first { $0.id == id }
    }

    /// A tap on a collapsed card expands it — see `expandedOverlay(_:)` for
    /// where the expanded state actually renders, and the "Manage Category"
    /// link inside it for how `CategoryDetailView` is still reached now
    /// that a tap here no longer navigates directly.
    private func categoryGrid(_ items: [CategorySpending]) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: 16
        ) {
            ForEach(items) { spending in
                Button {
                    expandedCategoryID = spending.id
                } label: {
                    CategoryCard(spending: spending, isExpanded: false)
                }
                .buttonStyle(CategoryCardPressStyle())
            }
        }
        .padding(.bottom, 22)
    }

    private func sectionLabel(_ title: String, count: Int) -> some View {
        Text("\(title.uppercased()) · \(count)")
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
            .padding(.bottom, 12)
    }

    // MARK: - Status strip

    /// `.idle` — a Category roster, like `ClientsView`'s own, has no
    /// urgency signal to flag; kept for layout consistency only.
    private var statusStrip: some View {
        HStack(spacing: 10) {
            StatusDot(.idle)
            Text(statusStripText)
                .pccPanelLabel()
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.bottom, 12)
    }

    private var statusStripText: String {
        let count = viewModel.categories.count
        let noun = count == 1 ? "CATEGORY" : "CATEGORIES"
        return "\(count) \(noun)"
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No Categories")
                .font(.headline)
            Text("Tap + to create your first Category.")
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

/// Shared create/edit form: the same sheet serves "New Category" and "Edit
/// Category" — a name field, nothing else (mirrors `ClientFormSheet`). Left
/// in the shared chassis look rather than a bespoke glass re-theme — a
/// `Form`'s native controls don't read as "liquid glass" however they're
/// dressed, so there's nothing this screen's own device would add here
/// (mirrors `AccountFormSheet`'s identical reasoning).
struct CategoryFormSheet: View {
    let title: String
    let onSave: (String) async -> Void

    @State private var name: String
    @Environment(\.dismiss) private var dismiss

    init(title: String, initialName: String, onSave: @escaping (String) async -> Void) {
        self.title = title
        self.onSave = onSave
        self._name = State(initialValue: initialName)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .pccField()
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
                        let name = trimmedName
                        Task {
                            await onSave(name)
                            dismiss()
                        }
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
    }
}

/// A Category's detail screen (ticket #39): the Category's name read-only at
/// the top (editing moved here from the list row, via the toolbar's "Edit"
/// button — same `CategoryFormSheet`/`onSave` wiring as before), plus a
/// "Subcategories" section listing the Category's Subcategories with
/// add/edit/delete — the same shape `ProjectDetailView` already has for
/// Sprints. Left unthemed beyond what it inherits from the environment,
/// same reasoning as `CategoryFormSheet`.
struct CategoryDetailView: View {
    let category: PCCCategory
    @ObservedObject var viewModel: CategoriesViewModel
    @ObservedObject var subcategoriesViewModel: SubcategoriesViewModel

    @State private var isPresentingEditSheet = false
    @State private var isPresentingNewSubcategorySheet = false
    @State private var editingSubcategory: Subcategory?

    /// The freshest known copy of `category` — falls back to the value
    /// passed in if `viewModel.categories` hasn't (yet) reflected an edit.
    private var currentCategory: PCCCategory {
        viewModel.categories.first(where: { $0.id == category.id }) ?? category
    }

    var body: some View {
        List {
            Section {
                Text(currentCategory.name)
                    .font(.title3)
            }
            .panelRows()
            Section("Subcategories") {
                if subcategoriesViewModel.subcategories.isEmpty {
                    Text("No Subcategories yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(subcategoriesViewModel.subcategories) { subcategory in
                        Button {
                            editingSubcategory = subcategory
                        } label: {
                            Text(subcategory.name)
                        }
                        #if os(macOS)
                        .buttonStyle(.plain)
                        #endif
                    }
                    .onDelete { offsets in
                        let toDelete = offsets.map { subcategoriesViewModel.subcategories[$0] }
                        Task {
                            for subcategory in toDelete {
                                await subcategoriesViewModel.deleteSubcategory(subcategory)
                            }
                        }
                    }
                }
                Button {
                    isPresentingNewSubcategorySheet = true
                } label: {
                    Label("Add Subcategory", systemImage: "plus")
                }
            }
            .panelRows()
        }
        .panelScreenBackground()
        .navigationTitle(currentCategory.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    isPresentingEditSheet = true
                }
            }
        }
        .task { await subcategoriesViewModel.load() }
        .refreshable { await subcategoriesViewModel.load() }
        .alert("Error", isPresented: isShowingSubcategoriesError, presenting: subcategoriesViewModel.errorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .sheet(isPresented: $isPresentingEditSheet) {
            CategoryFormSheet(title: "Edit Category", initialName: currentCategory.name) { name in
                await viewModel.updateCategory(currentCategory, name: name)
            }
        }
        .sheet(isPresented: $isPresentingNewSubcategorySheet) {
            SubcategoryFormSheet(title: "New Subcategory", initialName: "") { name in
                await subcategoriesViewModel.createSubcategory(name: name)
            }
        }
        .sheet(item: $editingSubcategory) { subcategory in
            SubcategoryFormSheet(title: "Edit Subcategory", initialName: subcategory.name) { name in
                await subcategoriesViewModel.updateSubcategory(subcategory, name: name)
            }
        }
    }

    private var isShowingSubcategoriesError: Binding<Bool> {
        Binding(
            get: { subcategoriesViewModel.errorMessage != nil },
            set: { isShowing in if !isShowing { subcategoriesViewModel.errorMessage = nil } }
        )
    }
}

/// Shared create/edit form: the same sheet serves "New Subcategory" and
/// "Edit Subcategory" — a name field, nothing else (mirrors
/// `CategoryFormSheet`). A Subcategory's Category isn't editable here — it's
/// set at creation and never reassigned (`CONTEXT.md`).
struct SubcategoryFormSheet: View {
    let title: String
    let onSave: (String) async -> Void

    @State private var name: String
    @Environment(\.dismiss) private var dismiss

    init(title: String, initialName: String, onSave: @escaping (String) async -> Void) {
        self.title = title
        self.onSave = onSave
        self._name = State(initialValue: initialName)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .pccField()
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
                        let name = trimmedName
                        Task {
                            await onSave(name)
                            dismiss()
                        }
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
    }
}

// MARK: - Category Glass theme

extension ScreenTheme {
    /// `CategoriesView`'s own vibe: the same real liquid glass as
    /// `AccountsView` — plain white/black with no color in the
    /// background, a genuine Material-backed bubble shape rather than a
    /// flat frosted rectangle — reused rather than shared across files
    /// since every other screen's `ScreenTheme` is likewise declared
    /// `fileprivate` to its own screen file. `signalGreen`/`signalRed` are
    /// overridden (unlike most other screens) for the same reason
    /// `AccountsView`'s are: the Spent/Received figure's color is this
    /// screen's actual signature accent.
    fileprivate static let categoryGlass = ScreenTheme(
        panelVoid: { $0 == .dark ? Color.black : Color.white },
        panelSurface: { $0 == .dark ? Color(hex: 0x121212) : Color(hex: 0xF7F7F7) },
        panelLine: { $0 == .dark ? Color(hex: 0x2A2A2A) : Color(hex: 0xE3E3E3) },
        accent: { $0 == .dark ? Color(hex: 0x45C989) : Color(hex: 0x157A4C) },
        signalGreen: { $0 == .dark ? Color(hex: 0x45C989) : Color(hex: 0x157A4C) },
        signalAmber: ScreenTheme.default.signalAmber,
        signalRed: { $0 == .dark ? Color(hex: 0xE2776A) : Color(hex: 0xB23226) }
    )
}

// MARK: - Dot grid background

/// A hairline dot grid, almost invisible — enough for a glass card's
/// Material blur to have some texture to work with, without reading as a
/// "background." Duplicated from `AccountsView.swift` rather than shared
/// (that one's `private` to its own file) — the same per-file bespoke-
/// device convention every other screen's bespoke `Shape`s already follow
/// (e.g. `CourseView.swift`'s `DashedLine` and `TransactionsView.swift`'s
/// `PerforationLine` are two separate small dashed-line shapes, not one
/// shared utility).
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

/// The tap feedback every collapsed `CategoryCard` button uses — a brief
/// press-down scale dip, same device as `PCCControlChipStyle` in
/// `FormControls.swift` (`FormControls.swift:57`) but scoped to this
/// screen's own card size rather than a small chip, so it's its own
/// declaration rather than a reuse of that one.
private struct CategoryCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Category card

/// This screen's signature: a real liquid-glass bubble (same device as
/// `AccountsView.AccountBubble` — a `Material`-backed shape, a tint
/// gradient, a blurred specular highlight, a hairline rim). Used two ways:
/// `isExpanded: false` as the plain collapsed grid cell, and
/// `isExpanded: true` as the single centered card
/// `CategoriesContent.expandedOverlay(_:)` paints above a dimmed scrim for
/// whichever Category was tapped (see that method's own doc comment for why
/// the expansion is a centered modal rather than something drawn in place
/// by the grid cell itself).
private struct CategoryCard: View {
    let spending: CategorySpending
    let isExpanded: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    private static let baseHeight: CGFloat = 140
    private static let cornerRadius: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(spending.category.name)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(2)
            Text(spending.isIncome ? "RECEIVED" : "SPENT")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(.secondary)
                .padding(.top, 10)
            Text(Self.formattedAmount(spending.headlineTotal, isIncome: spending.isIncome))
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(amountColor)
                .shadow(color: amountColor.opacity(colorScheme == .dark ? 0.5 : 0.28), radius: 10)
                .padding(.top, 2)
            if isExpanded {
                topEntries
                    .padding(.top, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: Self.baseHeight, alignment: .topLeading)
        .background(bubbleBackground)
    }

    // MARK: Top entries (expanded reveal)

    @ViewBuilder
    private var topEntries: some View {
        let entries = spending.topTransactions(limit: 3)
        VStack(alignment: .leading, spacing: 6) {
            Rectangle()
                .fill(theme.panelLine(colorScheme))
                .frame(height: 1)
                .opacity(0.7)
                .padding(.bottom, 2)
            if entries.isEmpty {
                Text("No entries yet")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Self.entryLabel(entry))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(Self.formattedAmount(entry.amount, isIncome: spending.isIncome))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(amountColor)
                    }
                }
            }
        }
    }

    /// A Transaction's own notes if it has any, else its date — the
    /// biggest-entries reveal has no Account name to show without wiring a
    /// third loaded list (`AccountsAPIClient`) into this view model purely
    /// for a hover tooltip, so this stays with data the Transaction itself
    /// already carries.
    private static func entryLabel(_ transaction: Transaction) -> String {
        if let notes = transaction.notes, !notes.isEmpty {
            return notes
        }
        return Self.dateFormatter.string(from: transaction.date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    // MARK: Glass

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
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.08), radius: 16, x: 0, y: 8)
    }

    private var specularHighlight: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [.white.opacity(colorScheme == .dark ? 0.22 : 0.55), .clear],
                    center: .center, startRadius: 0, endRadius: 70
                )
            )
            .frame(width: 130, height: 70)
            .rotationEffect(.degrees(-12))
            .offset(x: -40, y: -36)
            .blur(radius: 8)
            .allowsHitTesting(false)
    }

    private var amountColor: Color {
        spending.isIncome ? theme.signalGreen(colorScheme) : theme.signalRed(colorScheme)
    }

    private static func formattedAmount(_ amount: Double, isIncome: Bool) -> String {
        let signed = isIncome ? amount : -amount
        return signed.formatted(.currency(code: "PHP").sign(strategy: .always()))
    }
}
