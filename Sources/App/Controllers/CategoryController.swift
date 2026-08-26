import Fluent
import Vapor

struct CategoryResponse: Content {
    let id: UUID
    let name: String

    init(_ category: PCCCategory) throws {
        self.id = try category.requireID()
        self.name = category.name
    }
}

struct SaveCategoryRequest: Content {
    let name: String
}

/// Ticket #39: Category CRUD (`CONTEXT.md`) — a plain CRUD surface, same
/// shape as `ClientController`/`CourseController`.
struct CategoryController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let categories = routes.grouped("categories")
        categories.get(use: index)
        categories.post(use: create)
        categories.group(":categoryID") { category in
            category.put(use: update)
            category.delete(use: delete)
        }
    }

    /// Lists every Category — same "no per-owner scoping" reasoning as
    /// `AccountController.index` (single-owner system, ADR-0001).
    func index(req: Request) async throws -> [CategoryResponse] {
        try await PCCCategory.query(on: req.db).all().map(CategoryResponse.init)
    }

    func create(req: Request) async throws -> CategoryResponse {
        let payload = try req.content.decode(SaveCategoryRequest.self)
        let category = PCCCategory(name: try Self.validatedName(payload.name))
        try await category.save(on: req.db)
        return try CategoryResponse(category)
    }

    func update(req: Request) async throws -> CategoryResponse {
        guard let category = try await findCategory(req: req) else {
            throw Abort(.notFound)
        }
        let payload = try req.content.decode(SaveCategoryRequest.self)
        category.name = try Self.validatedName(payload.name)
        try await category.save(on: req.db)
        return try CategoryResponse(category)
    }

    /// Cascade-deletes this Category's Subcategories (`CreateSubcategory`'s
    /// `.cascade` FK) and orphans (sets null on) any referencing
    /// Transaction's `categoryID`/`subcategoryID` (`AddCategoryToTransaction`'s
    /// `.setNull` FKs) rather than blocking the delete — the opposite
    /// tradeoff from ticket #38's Account/Transaction guard, since a
    /// Transaction's Category is optional where its Account is required.
    /// Unlike `AccountController.delete`/`ClientController.delete`, there's
    /// no application-level guard here: the database's own FK actions are
    /// what produce this AC, not a check before `.delete()`.
    func delete(req: Request) async throws -> HTTPStatus {
        guard let category = try await findCategory(req: req) else {
            throw Abort(.notFound)
        }
        try await category.delete(on: req.db)
        return .noContent
    }

    /// A Category is created/edited "with a name" — reject an empty or
    /// whitespace-only one, mirroring `ClientController`'s name check.
    private static func validatedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw Abort(.badRequest, reason: "name must not be empty")
        }
        return trimmed
    }

    private func findCategory(req: Request) async throws -> PCCCategory? {
        guard let id = req.parameters.get("categoryID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        return try await PCCCategory.find(id, on: req.db)
    }
}
