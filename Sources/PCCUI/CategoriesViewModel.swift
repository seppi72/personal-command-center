import Foundation

/// Holds the Categories screen's state and talks to the backend through a
/// `CategoriesAPIClient`. Kept separate from `CategoriesView` so the view
/// stays a thin rendering of this state (mirrors `ClientsViewModel`'s split).
///
/// `ObservableObject` rather than the newer `@Observable` macro, since that
/// macro needs iOS 17/macOS 14 and this package targets iOS 16/macOS 13.
@MainActor
public final class CategoriesViewModel: ObservableObject {
    @Published public private(set) var categories: [PCCCategory] = []
    @Published public var errorMessage: String?
    @Published public private(set) var isLoading = false

    private let client: CategoriesAPIClient
    private let subcategoriesClient: SubcategoriesAPIClient

    public init(client: CategoriesAPIClient, subcategoriesClient: SubcategoriesAPIClient) {
        self.client = client
        self.subcategoriesClient = subcategoriesClient
    }

    /// Builds the `SubcategoriesViewModel` for one Category's detail screen,
    /// scoped to that Category's id — `CategoryDetailView` needs a
    /// `SubcategoriesAPIClient` and a `categoryID`, and this is where both
    /// are available together (mirrors `ProjectsViewModel.makeSprintsViewModel`).
    public func makeSubcategoriesViewModel(for category: PCCCategory) -> SubcategoriesViewModel {
        SubcategoriesViewModel(client: subcategoriesClient, categoryID: category.id)
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        await run(verb: "load") {
            categories = try await client.listCategories()
        }
    }

    public func createCategory(name: String) async {
        await run(verb: "create") {
            categories.append(try await client.createCategory(name: name))
        }
    }

    public func updateCategory(_ existing: PCCCategory, name: String) async {
        await run(verb: "update") {
            let updated = try await client.updateCategory(id: existing.id, name: name)
            if let index = categories.firstIndex(where: { $0.id == updated.id }) {
                categories[index] = updated
            }
        }
    }

    public func deleteCategory(_ existing: PCCCategory) async {
        await run(verb: "delete") {
            try await client.deleteCategory(id: existing.id)
            categories.removeAll { $0.id == existing.id }
        }
    }

    /// Runs a mutation against `categories`, keeping every method's
    /// success/failure handling (clear the error, re-sort by name; on
    /// failure surface a message) in one shape instead of four copies
    /// (mirrors `ClientsViewModel.run`).
    private func run(verb: String, _ operation: () async throws -> Void) async {
        do {
            try await operation()
            categories.sort { $0.name < $1.name }
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't \(verb) Category: \(error.localizedDescription)"
        }
    }
}
