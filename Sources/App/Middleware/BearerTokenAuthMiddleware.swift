import Vapor

/// Single-owner auth: rejects any request that doesn't carry a `Bearer` token
/// matching one of the tokens issued to the owner's devices (ADR-0001 — no
/// multi-user account system, so a shared/per-device static token is enough).
struct BearerTokenAuthMiddleware: AsyncMiddleware {
    let validTokens: Set<String>

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard
            let bearer = request.headers.bearerAuthorization,
            validTokens.contains(bearer.token)
        else {
            throw Abort(.unauthorized)
        }
        return try await next.respond(to: request)
    }
}
