import SwiftUI

/// Minimal Mac/iOS screen for ticket #17: lists Clients, and supports
/// creating, editing (renaming), and deleting one. One shared SwiftUI view
/// for both platforms — no platform-specific chrome, per the ticket's
/// "minimal" scope (mirrors `ProjectsView`).
public struct ClientsView: View {
    @ObservedObject private var viewModel: ClientsViewModel
    @State private var isPresentingNewClientSheet = false
    @State private var editingClient: PCCClient?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    public init(viewModel: ClientsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            Group {
                if viewModel.clients.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    clientList
                }
            }
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

    private var clientList: some View {
        List {
            Section {
                statusStrip
            }
            Section {
                ForEach(viewModel.clients) { client in
                    Button {
                        editingClient = client
                    } label: {
                        Text(client.name)
                    }
                    #if os(macOS)
                    .buttonStyle(.plain)
                    #endif
                }
                .onDelete { offsets in
                    let toDelete = offsets.map { viewModel.clients[$0] }
                    Task {
                        for client in toDelete {
                            await viewModel.deleteClient(client)
                        }
                    }
                }
                .panelRows()
            }
        }
        .panelScreenBackground()
    }

    // MARK: - Status strip

    /// `.idle` rather than `.nominal`/`.critical` — a Client roster has no
    /// urgency signal of its own to flag (`PanelStatus.idle`'s own doc
    /// comment: "no signal to show," not "nothing wrong"). Kept for layout
    /// consistency with every other list screen's strip rather than
    /// inventing a fake threshold this data has no basis for.
    private var statusStrip: some View {
        HStack(spacing: 10) {
            StatusDot(.idle)
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
                .fill(theme.panelLine(colorScheme))
                .frame(height: 1),
            alignment: .bottom
        )
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
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
