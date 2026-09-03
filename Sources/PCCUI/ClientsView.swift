import SwiftUI

/// Minimal Mac/iOS screen for ticket #17: lists Clients, and supports
/// creating, editing (renaming), and deleting one. One shared SwiftUI view
/// for both platforms — no platform-specific chrome, per the ticket's
/// "minimal" scope (mirrors `ProjectsView`).
///
/// On the shared Liquid Glass system since issue #69 — a grid of
/// `ClientCard` bubbles (mirrors `CategoriesView`'s/`ProjectsView`'s own
/// grid+expand shape), replacing the earlier card-index costume (the
/// ivory/oxblood `ScreenTheme.cardIndex` `git log` on this file still
/// shows). Tapping a card expands it into a centered overlay showing that
/// Client's Projects as its "recent work"; editing moved into that overlay
/// too, since a tap on the collapsed card is now spent on the expand
/// gesture instead of opening the edit sheet directly.
public struct ClientsView: View {
    @ObservedObject private var viewModel: ClientsViewModel

    public init(viewModel: ClientsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ClientsContent(viewModel: viewModel)
            .screenTheme(.liquidGlass)
    }
}

/// The screen's actual content — split out from `ClientsView` itself so
/// `.screenTheme(.liquidGlass)` (applied in that struct's body, above) is
/// genuinely in effect by the time this struct's own `body` reads
/// `@Environment(\.screenTheme)`. See `View.screenTheme(_:)`'s doc comment
/// in `PCCChassis.swift` for why the split is required.
private struct ClientsContent: View {
    @ObservedObject var viewModel: ClientsViewModel
    @State private var isPresentingNewClientSheet = false
    @State private var editingClient: PCCClient?

    /// Which card (if any) is currently expanded — tapping a collapsed grid
    /// card sets this; tapping the scrim, the close button, or the same
    /// card again clears it. Mirrors
    /// `CategoriesContent.expandedCategoryID`/`ProjectsContent.expandedProjectID`;
    /// unlike Projects, a Client's "recent work" (its Projects) is already
    /// held on `ClientsViewModel`, so expanding here needs no extra
    /// per-card view model.
    @State private var expandedClientID: UUID?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.clients.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    clientScroll
                }
            }
            .background(GlassScreenBackground())
            .navigationTitle("Clients")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingNewClientSheet = true
                    } label: {
                        Label("Add Client", systemImage: "plus")
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
            .sheet(isPresented: $isPresentingNewClientSheet) {
                ClientFormSheet(title: "New Client", initialName: "") { name in
                    await viewModel.createClient(name: name)
                }
            }
            .sheet(item: $editingClient) { client in
                ClientFormSheet(title: "Edit Client", initialName: client.name) { name in
                    await viewModel.updateClient(client, name: name)
                }
            }
        }
    }

    /// A `ScrollView` of `ClientCard`s in a `LazyVGrid`, with a centered
    /// expand overlay above a dimmed scrim rather than something grown in
    /// place out of its source grid cell — the same shape, for the same two
    /// real-bug reasons, `CategoriesContent.categoryScroll`'s own doc
    /// comment records in full (`LazyVGrid` not honoring `zIndex` across
    /// its own cells, and a grown-in-place transition never actually
    /// reading as "growing").
    private var clientScroll: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    statusStrip
                    clientGrid
                }
                .padding(PCCChassis.outerMargin)
            }
            if let expandedClientID, let client = client(withID: expandedClientID) {
                expandedOverlay(client)
            }
        }
        // On the enclosing `ZStack`, not the conditional content itself, so
        // it governs the whole insert/remove transition below rather than
        // only in-place property changes.
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: expandedClientID)
    }

    private func client(withID id: UUID) -> PCCClient? {
        viewModel.clients.first { $0.id == id }
    }

    /// A tap on a collapsed card expands it — see
    /// `expandedOverlay(_:)` for where the expanded state, and the "Edit
    /// Client" button, actually render. Deletion stays on each card's own
    /// context menu, since a grid has no `List`-style swipe gesture to
    /// give it for free.
    private var clientGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: 16
        ) {
            ForEach(viewModel.clients) { client in
                Button {
                    expandedClientID = expandedClientID == client.id ? nil : client.id
                } label: {
                    ClientCard(client: client, projectCount: viewModel.projects(for: client).count, isExpanded: false)
                }
                .buttonStyle(ClientCardPressStyle())
                .contextMenu {
                    Button(role: .destructive) {
                        Task { await viewModel.deleteClient(client) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .padding(.top, 16)
    }

    /// The single floating, enlarged `ClientCard` for whichever Client is
    /// tapped — a dimmed scrim behind it (tap to dismiss), a close button
    /// on the card itself, and an "Edit Client" button reaching the same
    /// `ClientFormSheet` the collapsed card used to open directly, now that
    /// a tap there spends itself on expanding instead (mirrors
    /// `CategoriesContent.expandedOverlay(_:)`).
    private func expandedOverlay(_ client: PCCClient) -> some View {
        ZStack {
            // Its own opacity-only transition — kept separate from the
            // card's `.scale` transition below, same reasoning as
            // `CategoriesContent.expandedOverlay(_:)`.
            Rectangle()
                .fill(scrimColor)
                .ignoresSafeArea()
                .onTapGesture { expandedClientID = nil }
                .transition(.opacity)
            VStack(spacing: 14) {
                ClientCard(
                    client: client,
                    projectCount: viewModel.projects(for: client).count,
                    isExpanded: true,
                    projects: viewModel.projects(for: client)
                )
                .background(bubbleShadow)
                .overlay(alignment: .topTrailing) {
                    Button {
                        expandedClientID = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                }
                Button {
                    editingClient = client
                } label: {
                    Label("Edit Client", systemImage: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                }
                #if os(macOS)
                .buttonStyle(.plain)
                #endif
                .foregroundStyle(theme.accent(colorScheme))
            }
            .frame(maxWidth: 360)
            // Distinct identity per Client so switching which card is
            // expanded is a genuine remove-then-insert (each transitioning
            // on its own) rather than one view's content silently
            // swapping.
            .id(client.id)
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
        }
        .zIndex(1)
    }

    private var scrimColor: Color {
        Color.black.opacity(colorScheme == .dark ? 0.6 : 0.28)
    }

    /// A drop shadow behind the expanded card — kept off the shared
    /// `GlassBubble` itself (which the collapsed grid cells also use)
    /// since only the enlarged overlay instance needs the heavier "lifted
    /// toward the viewer" shadow.
    private var bubbleShadow: some View {
        RoundedRectangle(cornerRadius: GlassBubbleStyle.gridCell.cornerRadius, style: .continuous)
            .fill(Color.clear)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.55 : 0.16), radius: 26, x: 0, y: 14)
    }

    // MARK: - Status strip

    /// `.idle` rather than `.nominal`/`.critical` — a Client roster has no
    /// urgency signal of its own to flag (`PanelStatus.idle`'s own doc
    /// comment: "no signal to show," not "nothing wrong"). Kept for layout
    /// consistency with every other screen's strip rather than inventing
    /// a fake threshold this data has no basis for.
    private var statusStrip: some View {
        HStack(spacing: 10) {
            StatusDot(.idle)
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

    private var statusStripText: String {
        let count = viewModel.clients.count
        let noun = count == 1 ? "CLIENT" : "CLIENTS"
        return "\(count) \(noun)"
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No Clients")
                .font(.headline)
            Text("Tap + to create your first Client.")
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

/// Shared create/edit form: the same sheet serves "New Client" and "Edit
/// Client" — a name field, nothing else (mirrors `ProjectFormSheet` minus
/// the Deadline section, which doesn't apply to a Client).
struct ClientFormSheet: View {
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
            .glassScreenBackground()
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

/// The tap feedback every collapsed `ClientCard` button uses — a brief
/// press-down scale dip, the same device `CategoryCard`'s/`ProjectCard`'s
/// own press styles use, scoped separately per screen matching their own
/// precedent.
private struct ClientCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Client card

/// One Client's card: the shared `GlassBubble` surface (`.gridCell` size)
/// with this screen's own content on it — a monogram seal and a Project
/// count as the card's "short label plus a number." Used two ways:
/// `isExpanded: false` as the plain collapsed grid cell (a bare count, no
/// `projects` needed), and `isExpanded: true` as the single centered card
/// `ClientsContent.expandedOverlay(_:)` paints above a dimmed scrim,
/// additionally passed that Client's `projects` to reveal as its recent
/// work (mirrors `CategoryCard`'s/`ProjectCard`'s own two-ways-used shape).
private struct ClientCard: View {
    let client: PCCClient
    let projectCount: Int
    let isExpanded: Bool
    var projects: [Project] = []

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    private static let baseHeight: CGFloat = 140
    private static let style: GlassBubbleStyle = .gridCell

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                seal
                Text(client.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
            }
            Text(projectCount == 1 ? "PROJECT" : "PROJECTS")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(.secondary)
                .padding(.top, 10)
            Text("\(projectCount)")
                .font(.pccReadout(22))
                .foregroundStyle(theme.accent(colorScheme))
                .padding(.top, 2)
            if isExpanded {
                recentWork
                    .padding(.top, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: Self.baseHeight, alignment: .topLeading)
        .glassBubble(Self.style)
    }

    /// The embossed monogram — a raised card mark cut from the same glass
    /// as the bubble it sits inside (`GlassBubble.tint(for:)`/`.rimColor`,
    /// the same device `AccountsView`'s own round type-icon well uses)
    /// rather than an opaque panel-surface fill, now that this card is
    /// genuine Material-backed glass rather than card-index stock.
    private var seal: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay(Circle().fill(GlassBubble.tint(for: colorScheme)))
            .overlay(
                Circle().strokeBorder(GlassBubble.rimColor(theme, colorScheme), lineWidth: GlassBubble.rimWidth)
            )
            .overlay(
                Text(monogram)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.accent(colorScheme))
            )
            .frame(width: 32, height: 32)
    }

    private var monogram: String {
        String(client.name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    // MARK: Recent work (expanded reveal)

    @ViewBuilder
    private var recentWork: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle()
                .fill(theme.panelLine(colorScheme))
                .frame(height: 1)
                .opacity(0.7)
                .padding(.bottom, 2)
            if projects.isEmpty {
                Text("No Projects yet")
                    .font(.system(size: 11))
                    .italic()
                    .foregroundStyle(.secondary)
            } else {
                ForEach(projects) { project in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("·")
                            .foregroundStyle(theme.accent(colorScheme))
                        Text(project.name)
                            .lineLimit(1)
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}
