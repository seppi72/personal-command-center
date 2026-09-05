import Foundation

/// Holds one Category's Subcategories screen state and talks to the backend
/// through a `SubcategoriesAPIClient`. Scoped to a single `categoryID` given
/// at `init` — a Subcategory has no meaning outside a Category, so unlike
/// `CategoriesViewModel` there's no unscoped "all Subcategories" list. Kept
/// separate from its view so the view stays a thin rendering of this state
/// (mirrors `WorkViewModel`'s split).
///
/// `ObservableObject` rather than the newer `@Observable` macro, since that
/// macro needs iOS 17/macOS 14 and this package targets iOS 16/macOS 13.
@MainActor
public final class SubcategoriesViewModel: ObservableObject {
    @Published public private(set) var subcategories: [Subcategory] = []
    @Published public var errorMessage: String?
    @Published public private(set) var isLoading = false

    private let client: SubcategoriesAPIClient
    private let categoryID: UUID

    public init(client: SubcategoriesAPIClient, categoryID: UUID) {
        self.client = client
        self.categoryID = categoryID
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        await run(verb: "load") {
            subcategories = try await client.listSubcategories(categoryID: categoryID)
        }
    }

    public func createSubcategory(name: String) async {
        await run(verb: "create") {
            subcategories.append(try await client.createSubcategory(categoryID: categoryID, name: name))
        }
    }

    public func updateSubcategory(_ existing: Subcategory, name: String) async {
        await run(verb: "update") {
            let updated = try await client.updateSubcategory(id: existing.id, name: name)
            if let index = subcategories.firstIndex(where: { $0.id == updated.id }) {
                subcategories[index] = updated
            }
        }
    }

    public func deleteSubcategory(_ existing: Subcategory) async {
        await run(verb: "delete") {
            try await client.deleteSubcategory(id: existing.id)
            subcategories.removeAll { $0.id == existing.id }
        }
    }

    /// Runs a mutation against `subcategories`, keeping every method's
    /// success/failure handling (clear the error, re-sort by name; on
    /// failure surface a message) in one shape instead of four copies
    /// (mirrors `WorkViewModel.run`).
    private func run(verb: String, _ operation: () async throws -> Void) async {
        do {
            try await operation()
            subcategories.sort { $0.name < $1.name }
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't \(verb) Subcategory: \(error.localizedDescription)"
        }
    }
}
