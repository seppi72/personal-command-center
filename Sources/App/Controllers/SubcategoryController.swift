import Fluent
import Vapor

struct SubcategoryResponse: Content {
    let id: UUID
    let name: String
    let categoryID: UUID

    init(_ subcategory: Subcategory) throws {
        self.id = try subcategory.requireID()
        self.name = subcategory.name
        self.categoryID = subcategory.$category.id
    }
}

/// A Subcategory's Category is set at creation and never reassigned — same
/// "immutable parent" reasoning `SprintController`'s own
/// `SaveSprintRequest`/`UpdateSprintRequest` split documents — so
/// `categoryID` only appears here, not in `UpdateSubcategoryRequest`.
struct SaveSubcategoryRequest: Content {
    let categoryID: UUID
    let name: String
}

struct UpdateSubcategoryRequest: Content {
    let name: String
}

/// Ticket #39: Subcategory CRUD (`CONTEXT.md`) — same shape as
/// `SprintController`: `GET /v1/subcategories` requires `?categoryID=`
/// rather than listing every Subcategory globally, since a Subcategory has
/// no meaning outside the Category it's scoped to.
struct SubcategoryController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let subcategories = routes.grouped("subcategories")
        subcategories.get(use: index)
        subcategories.post(use: create)
        subcategories.group(":subcategoryID") { subcategory in
            subcategory.put(use: update)
            subcategory.delete(use: delete)
        }
    }

    /// Lists the Subcategories in one Category — `?categoryID=` is required,
    /// mirroring `SprintController.index`'s required `?projectID=`.
    func index(req: Request) async throws -> [SubcategoryResponse] {
        guard let categoryID = req.query[UUID.self, at: "categoryID"] else {
            throw Abort(.badRequest, reason: "categoryID is required")
        }
        return try await Subcategory.query(on: req.db)
            .filter(\.$category.$id == categoryID)
            .all()
            .map(SubcategoryResponse.init)
    }

    func create(req: Request) async throws -> SubcategoryResponse {
        let payload = try req.content.decode(SaveSubcategoryRequest.self)
        guard try await PCCCategory.find(payload.categoryID, on: req.db) != nil else {
            throw Abort(.badRequest, reason: "no such Category")
        }
        let subcategory = Subcategory(name: try Self.validatedName(payload.name), categoryID: payload.categoryID)
        try await subcategory.save(on: req.db)
        return try SubcategoryResponse(subcategory)
    }

    func update(req: Request) async throws -> SubcategoryResponse {
        guard let subcategory = try await findSubcategory(req: req) else {
            throw Abort(.notFound)
        }
        let payload = try req.content.decode(UpdateSubcategoryRequest.self)
        subcategory.name = try Self.validatedName(payload.name)
        try await subcategory.save(on: req.db)
        return try SubcategoryResponse(subcategory)
    }

    /// Orphans (sets null on) any referencing Transaction's `subcategoryID`
    /// (`AddCategoryToTransaction`'s `.setNull` FK) rather than blocking the
    /// delete, mirroring `CategoryController.delete` — no application-level
    /// guard here either.
    func delete(req: Request) async throws -> HTTPStatus {
        guard let subcategory = try await findSubcategory(req: req) else {
            throw Abort(.notFound)
        }
        try await subcategory.delete(on: req.db)
        return .noContent
    }

    /// A Subcategory is created/edited "with a name" — reject an empty or
    /// whitespace-only one, mirroring `SprintController`'s name check.
    private static func validatedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw Abort(.badRequest, reason: "name must not be empty")
        }
        return trimmed
    }

    private func findSubcategory(req: Request) async throws -> Subcategory? {
        guard let id = req.parameters.get("subcategoryID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        return try await Subcategory.find(id, on: req.db)
    }
}
