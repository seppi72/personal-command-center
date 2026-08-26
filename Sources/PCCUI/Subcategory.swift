import Foundation

/// Client-side mirror of the backend's `SubcategoryResponse` — a label one
/// level under a Category (`CONTEXT.md`), scoped to the Category it was
/// created in for its lifetime.
public struct Subcategory: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public let categoryID: UUID

    public init(id: UUID, name: String, categoryID: UUID) {
        self.id = id
        self.name = name
        self.categoryID = categoryID
    }
}
