import Fluent
import Vapor

struct TransactionResponse: Content {
    let id: UUID
    let accountID: UUID
    let amount: Double
    let type: TransactionType
    let date: Date
    let notes: String?
    let categoryID: UUID?
    let subcategoryID: UUID?

    init(_ transaction: Transaction) throws {
        self.id = try transaction.requireID()
        self.accountID = transaction.$account.id
        self.amount = transaction.amount
        self.type = transaction.type
        self.date = transaction.date
        self.notes = transaction.notes
        self.categoryID = transaction.$category.id
        self.subcategoryID = transaction.$subcategory.id
    }
}

/// The same shape serves both create and edit — `accountID` travels inline
/// in the body either way, the same "container is mandatory from the start,
/// no valid unassigned state" shape `SaveTimeEntryRequest` already has
/// (`CONTEXT.md`'s Time Entry entry) — a Transaction can't exist accountless
/// any more than a Time Entry can exist container-less. `categoryID`/
/// `subcategoryID` (ticket #39) are optional and independent of each other —
/// not a single polymorphic container — but see
/// `TransactionController.verifyCategoryAndSubcategory` for the one
/// consistency rule enforced between them.
struct SaveTransactionRequest: Content {
    let accountID: UUID
    let amount: Double
    let type: TransactionType
    let date: Date
    let notes: String?
    let categoryID: UUID?
    let subcategoryID: UUID?
}

/// Ticket #37: Transaction CRUD (`CONTEXT.md`) — a plain CRUD surface, same
/// shape as `TimeEntryController`, minus overlap validation: unlike a Time
/// Entry's span, multiple Transactions on the same date are completely
/// normal.
struct TransactionController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let transactions = routes.grouped("transactions")
        transactions.get(use: index)
        transactions.post(use: create)
        transactions.group(":transactionID") { transaction in
            transaction.put(use: update)
            transaction.delete(use: delete)
        }
    }

    /// Lists every Transaction, or Transactions scoped to one Account
    /// and/or a `[start, end)` date range when `?accountID=`/`?start=`/
    /// `?end=` are given — combinable filters, mirroring
    /// `TimeEntryController.index`. `start`/`end` are parsed by hand with
    /// `ISO8601DateFormatter`, the same `WorkHoursController.validatedRange`
    /// reasoning: Vapor's query decoder defaults `Date` to
    /// `secondsSince1970`, unlike its JSON body decoder. Either bound may be
    /// given alone — unlike `WorkHoursController`'s rollups, a plain list
    /// doesn't need a dense range to bucket into, so neither is required.
    func index(req: Request) async throws -> [TransactionResponse] {
        var query = Transaction.query(on: req.db)
        if let accountID = req.query[UUID.self, at: "accountID"] {
            query = query.filter(\.$account.$id == accountID)
        }
        if let start = try Self.validatedQueryDate(req, at: "start") {
            query = query.filter(\.$date >= start)
        }
        if let end = try Self.validatedQueryDate(req, at: "end") {
            query = query.filter(\.$date < end)
        }
        return try await query.all().map(TransactionResponse.init)
    }

    func create(req: Request) async throws -> TransactionResponse {
        let payload = try req.content.decode(SaveTransactionRequest.self)
        try await verifyAccountExists(payload.accountID, req: req)
        try await Self.verifyCategoryAndSubcategory(categoryID: payload.categoryID, subcategoryID: payload.subcategoryID, req: req)
        let transaction = Transaction(
            amount: try Self.validatedAmount(payload.amount),
            type: payload.type,
            date: payload.date,
            notes: Self.normalizedNotes(payload.notes),
            accountID: payload.accountID,
            categoryID: payload.categoryID,
            subcategoryID: payload.subcategoryID
        )
        try await transaction.save(on: req.db)
        return try TransactionResponse(transaction)
    }

    /// Edits every field under the same validation as `create` — amount,
    /// type, date, notes, account, category, and subcategory all travel in
    /// the same `SaveTransactionRequest` this Transaction is simply
    /// overwritten with, mirroring `TimeEntryController.update`.
    func update(req: Request) async throws -> TransactionResponse {
        guard let transaction = try await findTransaction(req: req) else {
            throw Abort(.notFound)
        }
        let payload = try req.content.decode(SaveTransactionRequest.self)
        try await verifyAccountExists(payload.accountID, req: req)
        try await Self.verifyCategoryAndSubcategory(categoryID: payload.categoryID, subcategoryID: payload.subcategoryID, req: req)
        transaction.amount = try Self.validatedAmount(payload.amount)
        transaction.type = payload.type
        transaction.date = payload.date
        transaction.notes = Self.normalizedNotes(payload.notes)
        transaction.$account.id = payload.accountID
        transaction.$category.id = payload.categoryID
        transaction.$subcategory.id = payload.subcategoryID
        try await transaction.save(on: req.db)
        return try TransactionResponse(transaction)
    }

    /// No referencing-entity guard to worry about here, unlike
    /// `AccountController.delete` — nothing attaches to a Transaction the
    /// way a Transaction attaches to an Account.
    func delete(req: Request) async throws -> HTTPStatus {
        guard let transaction = try await findTransaction(req: req) else {
            throw Abort(.notFound)
        }
        try await transaction.delete(on: req.db)
        return .noContent
    }

    private func verifyAccountExists(_ accountID: UUID, req: Request) async throws {
        guard try await Account.find(accountID, on: req.db) != nil else {
            throw Abort(.badRequest, reason: "no such Account")
        }
    }

    /// Ticket #39: `categoryID`/`subcategoryID` are independent fields, not a
    /// single polymorphic container, but the AC's own enumeration of valid
    /// states — neither, a Category alone, or a Category *and* Subcategory
    /// together — rules out a `subcategoryID` whose `categoryID` is missing
    /// or belongs to a different Category. Verifies both exist and, when a
    /// `subcategoryID` is given, that its parent Category matches
    /// `categoryID` exactly (mirrors `TaskController.assignSprint`'s
    /// Sprint-belongs-to-Project check, one level down the hierarchy).
    private static func verifyCategoryAndSubcategory(categoryID: UUID?, subcategoryID: UUID?, req: Request) async throws {
        if let categoryID {
            guard try await PCCCategory.find(categoryID, on: req.db) != nil else {
                throw Abort(.badRequest, reason: "no such Category")
            }
        }
        guard let subcategoryID else { return }
        guard let subcategory = try await Subcategory.find(subcategoryID, on: req.db) else {
            throw Abort(.badRequest, reason: "no such Subcategory")
        }
        guard subcategory.$category.id == categoryID else {
            throw Abort(.badRequest, reason: "subcategoryID requires its parent categoryID")
        }
    }

    /// `amount` is a positive magnitude — `type` carries the sign
    /// (`Transaction.signedAmount`), so a zero or negative amount here would
    /// mean the sign is being double-applied by whoever sent it.
    private static func validatedAmount(_ amount: Double) throws -> Double {
        guard amount > 0 else {
            throw Abort(.badRequest, reason: "amount must be positive")
        }
        return amount
    }

    /// Notes are optional: missing, empty, and whitespace-only all collapse
    /// to "no notes" rather than persisting a blank string, mirroring
    /// `TimeEntryController.normalizedNotes`.
    private static func normalizedNotes(_ notes: String?) -> String? {
        guard let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func validatedQueryDate(_ req: Request, at key: String) throws -> Date? {
        guard let raw = req.query[String.self, at: key] else { return nil }
        guard let date = ISO8601DateFormatter().date(from: raw) else {
            throw Abort(.badRequest, reason: "\(key) must be an ISO 8601 date")
        }
        return date
    }

    private func findTransaction(req: Request) async throws -> Transaction? {
        guard let id = req.parameters.get("transactionID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        return try await Transaction.find(id, on: req.db)
    }
}
