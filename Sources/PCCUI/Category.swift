import Foundation

/// Client-side mirror of the backend's `CategoryResponse` — an owner-created
/// label for grouping Transactions by kind of spending (`CONTEXT.md`).
///
/// Named `PCCCategory` in Swift only, mirroring the backend model's own
/// `PCCCategory` (`Sources/App/Models/Category.swift`): an unqualified
/// `Category` collides with the Objective-C runtime's own `Category` typedef
/// (`objc/runtime.h`, pulled in transitively through Foundation on Darwin),
/// the same kind of collision `PCCTask` already sidesteps this way. The
/// domain term "Category" is what shows up in the JSON API (`categoryID`)
/// and UI text.
public struct PCCCategory: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}
