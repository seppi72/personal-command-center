import Testing
import VaporTesting

@testable import App

/// Exercises the seam agreed in the spec: a real HTTP request against a
/// running Vapor app, backed by a real (test) Postgres database — no mocked
/// services, no reaching past the HTTP boundary.
// Serialized: every test hits the same real Postgres test database (no
// per-test isolation), so concurrent runs would race on migrations and on
// the shared HealthPing row.
@Suite("Health", .serialized)
struct HealthTests {
    @discardableResult
    private func withHealthApp<T>(_ test: (Application) async throws -> T) async throws -> T {
        try await withApp(configure: { app in
            setenv("AUTH_TOKENS", "test-token-one", 1)
            try await configure(app)
        }) { app in
            let result = try await test(app)
            try await HealthPing.query(on: app.db).delete()
            return result
        }
    }

    @Test("rejects requests without a bearer token")
    func healthWithoutTokenIsRejected() async throws {
        try await withHealthApp { app in
            try await app.testing().test(.GET, "/v1/health", afterResponse: { res async in
                #expect(res.status == .unauthorized)
            })
        }
    }

    @Test("rejects requests with an invalid bearer token")
    func healthWithInvalidTokenIsRejected() async throws {
        try await withHealthApp { app in
            try await app.testing().test(
                .GET, "/v1/health",
                headers: ["Authorization": "Bearer not-a-real-token"],
                afterResponse: { res async in
                    #expect(res.status == .unauthorized)
                }
            )
        }
    }

    @Test("returns 200 for a request with a valid bearer token")
    func healthWithValidTokenSucceeds() async throws {
        try await withHealthApp { app in
            try await app.testing().test(
                .GET, "/v1/health",
                headers: ["Authorization": "Bearer test-token-one"],
                afterResponse: { res async throws in
                    #expect(res.status == .ok)
                    let body = try res.content.decode(HealthResponse.self)
                    #expect(body.status == "ok")
                }
            )
        }
    }

    /// Two separate client instances using the same token against the same
    /// running backend must see one shared, advancing count — not two
    /// independent counters — proving there's no per-client local store to
    /// drift out of sync (ADR-0001). Each `.test(...)` call here is its own
    /// request, standing in for a separate client instance (e.g. the Mac app
    /// and the iOS app each making their own call with the token they were
    /// issued).
    @Test("two clients using the same token against the same backend see identical state")
    func twoClientsShareIdenticalBackendState() async throws {
        try await withHealthApp { app in
            var firstClientCount = 0
            try await app.testing().test(
                .GET, "/v1/health",
                headers: ["Authorization": "Bearer test-token-one"],
                afterResponse: { res async throws in
                    firstClientCount = try res.content.decode(HealthResponse.self).pingCount
                }
            )

            try await app.testing().test(
                .GET, "/v1/health",
                headers: ["Authorization": "Bearer test-token-one"],
                afterResponse: { res async throws in
                    let body = try res.content.decode(HealthResponse.self)
                    #expect(body.pingCount == firstClientCount + 1)
                }
            )
        }
    }
}
