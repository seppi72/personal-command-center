import SwiftUI

/// Minimal Mac/iOS screen for ticket #17: lists Clients, and supports
/// creating, editing (renaming), and deleting one. One shared SwiftUI view
/// for both platforms — no platform-specific chrome, per the ticket's
/// "minimal" scope (mirrors `ProjectsView`).
public struct ClientsView: View {
    @ObservedObject private var viewModel: ClientsViewModel

    public init(viewModel: ClientsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ClientsContent(viewModel: viewModel)
            .screenTheme(.cardIndex)
    }
}

/// The screen's actual content — split out from `ClientsView` itself so
/// `.screenTheme(.cardIndex)` (applied in that struct's body, above) is
/// genuinely in effect by the time this struct's own `body` reads
/// `@Environment(\.screenTheme)`. See `View.screenTheme(_:)`'s doc comment
/// in `PCCChassis.swift` for why the split is required.
private struct ClientsContent: View {
    @ObservedObject var viewModel: ClientsViewModel
    @State private var isPresentingNewClientSheet = false
    @State private var editingClient: PCCClient?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.clients.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    clientGrid
                }
            }
            .background(PanelBackground())
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

    /// A 3-column grid of Client cards rather than a flat list — each
    /// card sized to its own content (roughly square with few Projects,
    /// taller with more) and showing that Client's Projects directly,
    /// per the brief for this screen's own vibe. Swipe-to-delete doesn't
    /// exist in a grid the way `List`'s `.onDelete` gave it for free, so
    /// deletion moved to each card's own context menu.
    private var clientGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                statusStrip
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 16
                ) {
                    ForEach(viewModel.clients) { client in
                        ClientCard(
                            client: client,
                            projects: viewModel.projects(for: client),
                            onTap: { editingClient = client },
                            onDelete: { Task { await viewModel.deleteClient(client) } }
                        )
                    }
                }
                .padding(.top, 16)
            }
            .padding(PCCChassis.outerMargin)
        }
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
        .padding(.bottom, 10)
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

// MARK: - Card Index theme

extension ScreenTheme {
    /// `ClientsView`'s own vibe: a card-index/rolodex — ivory index-card
    /// stock and an oxblood accent, distinct from Commitments' warmer,
    /// dustier rose next door in the sidebar. This screen's material is
    /// card stock and leather, not notebook paper. Signal colors left as
    /// `ScreenTheme.default`'s.
    fileprivate static let cardIndex = ScreenTheme(
        panelVoid: { $0 == .dark ? Color(hex: 0x1C1712) : Color(hex: 0xEFEAD9) },
        panelSurface: { $0 == .dark ? Color(hex: 0x2A241B) : Color(hex: 0xFFFEF9) },
        panelLine: { $0 == .dark ? Color(hex: 0x453A28) : Color(hex: 0xDDD3B8) },
        accent: { $0 == .dark ? Color(hex: 0xD98E8E) : Color(hex: 0x7A2E2E) },
        signalGreen: ScreenTheme.default.signalGreen,
        signalAmber: ScreenTheme.default.signalAmber,
        signalRed: ScreenTheme.default.signalRed
    )
}

// MARK: - Client card

/// This screen's signature: one Client per card in a 3-column grid,
/// each carrying an embossed monogram seal (the business-card mark a
/// real card index entry has) and that Client's own Projects listed
/// directly — sized to its content, so a Client with more Projects gets
/// a taller card instead of every card being forced to one fixed size.
private struct ClientCard: View {
    let client: PCCClient
    let projects: [Project]
    let onTap: () -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    seal
                    Text(client.name)
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .lineLimit(2)
                }
                Rectangle()
                    .fill(theme.panelLine(colorScheme))
                    .frame(height: 1)
                projectList
                Text(projectCountText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.panelSurface(colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(theme.panelLine(colorScheme), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.06), radius: 8, x: 0, y: 3)
            )
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

    /// The embossed monogram — a raised card mark, not a plain avatar
    /// circle: filled with the panel's own surface color and an inset
    /// shadow rather than a solid accent fill, so it reads as pressed
    /// into the card rather than pasted on top of it.
    private var seal: some View {
        Circle()
            .fill(theme.panelSurface(colorScheme))
            .overlay(Circle().strokeBorder(theme.panelLine(colorScheme), lineWidth: 1))
            .overlay(
                Text(monogram)
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .foregroundStyle(theme.accent(colorScheme))
            )
            .frame(width: 32, height: 32)
    }

    private var monogram: String {
        String(client.name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    @ViewBuilder
    private var projectList: some View {
        if projects.isEmpty {
            Text("No Projects yet")
                .font(.system(size: 12))
                .italic()
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 5) {
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

    private var projectCountText: String {
        projects.count == 1 ? "1 Project" : "\(projects.count) Projects"
    }
}
