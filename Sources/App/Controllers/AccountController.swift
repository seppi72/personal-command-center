import Fluent
import Vapor

struct AccountResponse: Content {
    let id: UUID
    let name: String
    let type: AccountType
    let classification: AccountClassification
    let openingBalance: Double
    let balance: Double

    /// `balance` is `openingBalance + Σ(Transactions)`
    /// (`docs/adr/0007-computed-balance-over-reconciliation.md`, ticket
    /// #37), passed in already computed rather than derived here: computing
    /// it needs a database round trip (`Transaction.netAmount`), which an
    /// `init` can't perform. `AccountController` is the single place that
    /// computes it before constructing this response, the same "derive it
    /// every response" shape `WorkHoursController` already uses for its
    /// rollup totals.
    init(_ account: Account, balance: Double) throws {
        self.id = try account.requireID()
        self.name = account.name
        self.type = account.type
        self.classification = account.type.classification
        self.openingBalance = account.openingBalance
        self.balance = balance
    }
}

struct CreateAccountRequest: Content {
    let name: String
    let type: AccountType
    let openingBalance: Double
}

/// Deliberately narrower than `CreateAccountRequest` — no `openingBalance`
/// field at all, not merely one that's ignored if sent. `openingBalance` is
/// immutable after creation (`Account`'s doc comment,
/// `docs/adr/0007-computed-balance-over-reconciliation.md`), a deliberate
/// exception to this codebase's usual PUT-replaces-everything convention
/// (contrast `TimeEntryController.update`, which does replace every field).
struct UpdateAccountRequest: Content {
    let name: String
    let type: AccountType
}

/// Ticket #36: Account CRUD (`CONTEXT.md`) — a plain CRUD surface, same
/// shape as `ProjectController`/`ClientController`, with one deliberate
/// deviation: `update` never writes `openingBalance`.
struct AccountController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let accounts = routes.grouped("accounts")
        accounts.get(use: index)
        accounts.post(use: create)
        accounts.group(":accountID") { account in
            account.put(use: update)
            account.delete(use: delete)
        }
    }

    /// Lists every Account with its Balance (`CONTEXT.md`) — no per-owner
    /// scoping, same "no per-client local store" reasoning as
    /// `ProjectController.index` (ADR-0001): this is a single-owner system.
    /// Balances come from one `Transaction.netAmountsByAccount` call rather
    /// than `computedBalance` per row — the same "load once, aggregate in
    /// memory" shape `WorkHoursController` uses, avoiding an N+1 query as
    /// the Account list grows.
    func index(req: Request) async throws -> [AccountResponse] {
        let accounts = try await Account.query(on: req.db).all()
        let netAmounts = try await Transaction.netAmountsByAccount(on: req.db)
        return try accounts.map { account in
            try AccountResponse(account, balance: account.openingBalance + (netAmounts[try account.requireID()] ?? 0))
        }
    }

    func create(req: Request) async throws -> AccountResponse {
        let payload = try req.content.decode(CreateAccountRequest.self)
        let account = Account(
            name: try Self.validatedName(payload.name),
            type: payload.type,
            openingBalance: payload.openingBalance
        )
        try await account.save(on: req.db)
        // No Transaction can already reference a brand-new Account, so its
        // Balance is trivially its opening balance — skip the round trip
        // `computedBalance` would otherwise make for a guaranteed-zero sum.
        return try AccountResponse(account, balance: account.openingBalance)
    }

    /// Edits `name`/`type` only — `openingBalance` isn't in
    /// `UpdateAccountRequest` at all, so there's nothing here that could
    /// touch it even by accident.
    func update(req: Request) async throws -> AccountResponse {
        guard let account = try await findAccount(req: req) else {
            throw Abort(.notFound)
        }
        let payload = try req.content.decode(UpdateAccountRequest.self)
        account.name = try Self.validatedName(payload.name)
        account.type = payload.type
        try await account.save(on: req.db)
        return try AccountResponse(account, balance: try await Self.computedBalance(for: account, on: req.db))
    }

    /// `openingBalance + Σ(Transactions)` (`CONTEXT.md`,
    /// `docs/adr/0007-computed-balance-over-reconciliation.md`) — the only
    /// place `AccountController` computes an Account's Balance, so `index`/
    /// `update`/`create` can't drift into three different formulas.
    private static func computedBalance(for account: Account, on db: any Database) async throws -> Double {
        try await account.openingBalance + Transaction.netAmount(forAccount: account.requireID(), on: db)
    }

    /// An Account is created/edited "with a name" — reject an empty or
    /// whitespace-only one, mirroring `ProjectController`/`ClientController`.
    private static func validatedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw Abort(.badRequest, reason: "name must not be empty")
        }
        return trimmed
    }

    /// No referencing-entity check before deleting, unlike
    /// `ProjectController`/`ClientController.delete`'s guard against
    /// orphaning a Time Entry (ticket #29) — deleting an Account still
    /// succeeds even with Transactions attached (ticket #37's AC), same
    /// `.cascade` FK fallback `CreateTransaction` gives it. The equivalent
    /// guard against a referencing Transaction is ticket #38, deliberately
    /// scoped out of this ticket.
    func delete(req: Request) async throws -> HTTPStatus {
        guard let account = try await findAccount(req: req) else {
            throw Abort(.notFound)
        }
        try await account.delete(on: req.db)
        return .noContent
    }

    private func findAccount(req: Request) async throws -> Account? {
        guard let id = req.parameters.get("accountID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        return try await Account.find(id, on: req.db)
    }
}
