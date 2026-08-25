import Foundation

/// Client-side mirror of the backend's `PCCClientResponse` — a grouping of
/// Projects, e.g. an employer or a freelance client (`CONTEXT.md`).
///
/// Named `PCCClient` in Swift, not `Client`, matching the backend model —
/// see `Sources/App/Models/PCCClient.swift`'s doc comment. The domain term
/// "Client" is what appears in the API paths/JSON and UI text.
public struct PCCClient: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}
