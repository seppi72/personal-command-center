import Fluent
import Vapor

struct HealthResponse: Content {
    let status: String
    let pingCount: Int
}

struct HealthController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get("health", use: index)
    }

    /// Increments the single shared `HealthPing` row and returns its new
    /// count. Two clients calling this in sequence see the count advance
    /// across calls rather than each starting back at 1 — proof the state
    /// lives in the database, not in per-client memory.
    func index(req: Request) async throws -> HealthResponse {
        let ping: HealthPing
        if let existing = try await HealthPing.query(on: req.db).first() {
            existing.count += 1
            try await existing.save(on: req.db)
            ping = existing
        } else {
            let created = HealthPing(count: 1)
            try await created.save(on: req.db)
            ping = created
        }
        return HealthResponse(status: "ok", pingCount: ping.count)
    }
}
