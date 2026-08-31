import SwiftUI

/// Minimal Mac/iOS screen for ticket #39: lists Categories, and supports
/// creating, editing (renaming), and deleting one. One shared SwiftUI view
/// for both platforms — no platform-specific chrome, per this codebase's
/// existing "minimal" scope (mirrors `ProjectsView`). Tapping a row navigates
/// into `CategoryDetailView` rather than opening the edit sheet directly —
/// same "editing moves to the detail screen's own toolbar" shape
/// `ProjectsView`'s own `ProjectDetailView` already has for Sprints.
public struct CategoriesView: View {
    @ObservedObject private var viewModel: CategoriesViewModel
    @State private var isPresentingNewCategorySheet = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenTheme) private var theme

    public init(viewModel: CategoriesViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            Group {
                if viewModel.categories.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    categoryList
                }
            }
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

    private var categoryList: some View {
        List {
            Section {
                statusStrip
            }
            Section {
                ForEach(viewModel.categories) { category in
                    NavigationLink {
                        CategoryDetailView(
                            category: category,
                            viewModel: viewModel,
                            subcategoriesViewModel: viewModel.makeSubcategoriesViewModel(for: category)
                        )
                    } label: {
                        Text(category.name)
                    }
                }
                .onDelete { offsets in
                    let toDelete = offsets.map { viewModel.categories[$0] }
                    Task {
                        for category in toDelete {
                            await viewModel.deleteCategory(category)
                        }
                    }
                }
                .panelRows()
            }
        }
        .panelScreenBackground()
    }

    // MARK: - Status strip

    /// `.idle` — a Category list, like `ClientsView`'s roster, has no
    /// urgency signal to flag; kept for layout consistency only.
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
/// Category" — a name field, nothing else (mirrors `ClientFormSheet`).
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
/// Sprints.
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
