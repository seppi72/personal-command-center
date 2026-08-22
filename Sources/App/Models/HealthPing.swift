import Fluent
import Vapor

/// A single, always-there row that `/v1/health` increments on every call.
///
/// Its only purpose is to prove the backend has no per-client local store to
/// drift out of sync (ADR-0001): every request that hits it, regardless of
/// which device sent it, reads and writes the same database row, so two
/// separate clients calling it in sequence see one shared, monotonically
/// increasing count rather than two independent counters.
final class HealthPing: Model, @unchecked Sendable {
    static let schema = "health_pings"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "count")
    var count: Int

    init() {}

    init(id: UUID? = nil, count: Int) {
        self.id = id
        self.count = count
    }
}
