import Fluent
import Vapor

struct TaskResponse: Content {
    let id: UUID
    let title: String
    let notes: String?
    let isComplete: Bool
    let projectID: UUID?

    init(_ task: PCCTask) throws {
        self.id = try task.requireID()
        self.title = task.title
        self.notes = task.notes
        self.isComplete = task.isComplete
        self.projectID = task.$project.id
    }
}

struct SaveTaskRequest: Content {
    let title: String
    let notes: String?
}

/// `projectID: nil` (or the key omitted entirely — Codable's synthesized
/// decoding treats a missing optional key the same as an explicit `null`)
/// both mean "make this Task Project-less".
struct AssignTaskProjectRequest: Content {
    let projectID: UUID?
}

struct TaskController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let tasks = routes.grouped("tasks")
        tasks.get(use: index)
        tasks.post(use: create)
        tasks.group(":taskID") { task in
            task.put(use: update)
            task.delete(use: delete)
            task.put("complete", use: markComplete)
            task.put("incomplete", use: markIncomplete)
            task.put("project", use: assignProject)
        }
    }

    /// Lists every Task, or Tasks scoped to one Project when `?projectID=`
    /// is given — the ticket's two listings as one endpoint rather than a
    /// second route, since it's the same query with an optional filter.
    func index(req: Request) async throws -> [TaskResponse] {
        var query = PCCTask.query(on: req.db)
        if let projectID = req.query[UUID.self, at: "projectID"] {
            query = query.filter(\.$project.$id == projectID)
        }
        return try await query.all().map(TaskResponse.init)
    }

    /// A Task is created "Project-less" — assignment is its own endpoint
    /// (`assignProject`), matching the AC's separate "assign a Task to a
    /// Project" criterion.
    func create(req: Request) async throws -> TaskResponse {
        let payload = try req.content.decode(SaveTaskRequest.self)
        let task = PCCTask(
            title: try Self.validatedTitle(payload.title),
            notes: Self.normalizedNotes(payload.notes)
        )
        try await task.save(on: req.db)
        return try TaskResponse(task)
    }

    func update(req: Request) async throws -> TaskResponse {
        guard let task = try await findTask(req: req) else {
            throw Abort(.notFound)
        }
        let payload = try req.content.decode(SaveTaskRequest.self)
        task.title = try Self.validatedTitle(payload.title)
        task.notes = Self.normalizedNotes(payload.notes)
        try await task.save(on: req.db)
        return try TaskResponse(task)
    }

    func delete(req: Request) async throws -> HTTPStatus {
        guard let task = try await findTask(req: req) else {
            throw Abort(.notFound)
        }
        try await task.delete(on: req.db)
        return .noContent
    }

    func markComplete(req: Request) async throws -> TaskResponse {
        try await setCompletion(true, req: req)
    }

    func markIncomplete(req: Request) async throws -> TaskResponse {
        try await setCompletion(false, req: req)
    }

    private func setCompletion(_ isComplete: Bool, req: Request) async throws -> TaskResponse {
        guard let task = try await findTask(req: req) else {
            throw Abort(.notFound)
        }
        task.isComplete = isComplete
        try await task.save(on: req.db)
        return try TaskResponse(task)
    }

    /// Assign, move, or remove (`projectID: null`) a Task's Project — all
    /// three ACs are the same write (set-or-clear the foreign key), not
    /// three different operations.
    func assignProject(req: Request) async throws -> TaskResponse {
        guard let task = try await findTask(req: req) else {
            throw Abort(.notFound)
        }
        let payload = try req.content.decode(AssignTaskProjectRequest.self)
        if let projectID = payload.projectID {
            guard try await Project.find(projectID, on: req.db) != nil else {
                throw Abort(.badRequest, reason: "no such Project")
            }
        }
        task.$project.id = payload.projectID
        try await task.save(on: req.db)
        return try TaskResponse(task)
    }

    /// A Task is created/edited "with a title" — reject an empty or
    /// whitespace-only one, mirroring `ProjectController`'s name check.
    private static func validatedTitle(_ title: String) throws -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw Abort(.badRequest, reason: "title must not be empty")
        }
        return trimmed
    }

    /// Notes are optional: missing, empty, and whitespace-only all collapse
    /// to "no notes" rather than persisting a blank string.
    private static func normalizedNotes(_ notes: String?) -> String? {
        guard let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func findTask(req: Request) async throws -> PCCTask? {
        guard let id = req.parameters.get("taskID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        return try await PCCTask.find(id, on: req.db)
    }
}
