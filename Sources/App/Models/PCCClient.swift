import Fluent
import Vapor

/// A grouping of Projects, e.g. an employer or a freelance client
/// (`CONTEXT.md`) — sits above Project, not beside it. Created directly by
/// the owner; there's no external source of "you have a new client" to mirror.
///
/// Named `PCCClient` in Swift only: an unqualified `Client` here would shadow
/// Vapor's own `Client` protocol (`app.client`/`req.client`), the same
/// problem `PCCTask` already sidesteps for `_Concurrency.Task`. The domain
/// term "Client" is what shows up everywhere that matters — the `schema`,
/// the JSON API, docs, and UI text.
final class PCCClient: Model, @unchecked Sendable {
    static let schema = "clients"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    init() {}

    init(id: UUID? = nil, name: String) {
        self.id = id
        self.name = name
    }
}
