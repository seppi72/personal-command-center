import Fluent
import Vapor

struct TaskResponse: Content {
    let id: UUID
    let title: String
    let notes: String?
    let isComplete: Bool
    let projectID: UUID?
    let dueDate: Date?
    let sprintID: UUID?

    init(_ task: PCCTask) throws {
        self.id = try task.requireID()
        self.title = task.title
        self.notes = task.notes
        self.isComplete = task.isComplete
        self.projectID = task.$project.id
        self.dueDate = task.dueDate
        self.sprintID = task.$sprint.id
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

/// `dueDate: nil` (or the key omitted entirely) clears the Task's Deadline —
/// same "missing means null" shape as `AssignTaskProjectRequest`.
struct SetTaskDeadlineRequest: Content {
    let dueDate: Date?
}

/// `sprintID: nil` (or the key omitted entirely) both mean "make this Task
/// Sprint-less" — same shape as `AssignTaskProjectRequest`.
struct AssignTaskSprintRequest: Content {
    let sprintID: UUID?
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
            task.put("deadline", use: setDeadline)
            task.put("sprint", use: assignSprint)
        }
    }

    /// Lists every Task, or Tasks scoped to one Project and/or one Sprint
    /// when `?projectID=`/`?sprintID=` are given — the ticket's listings as
    /// one endpoint rather than separate routes, since they're the same
    /// query with independent, combinable optional filters.
    func index(req: Request) async throws -> [TaskResponse] {
        var query = PCCTask.query(on: req.db)
        if let projectID = req.query[UUID.self, at: "projectID"] {
            query = query.filter(\.$project.$id == projectID)
        }
        if let sprintID = req.query[UUID.self, at: "sprintID"] {
            query = query.filter(\.$sprint.$id == sprintID)
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
    /// three different operations. Moving to a *different* Project than the
    /// Task's current one also clears its Sprint (ticket #18): a Sprint is
    /// scoped to the Project it was created in for its lifetime, so a Sprint
    /// that belonged to the old Project no longer applies. Leaving the
    /// `projectID` unchanged leaves the Sprint alone.
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
        if payload.projectID != task.$project.id {
            task.$sprint.id = nil
        }
        task.$project.id = payload.projectID
        try await task.save(on: req.db)
        return try TaskResponse(task)
    }

    /// Assign, move, or remove (`sprintID: null`) a Task's Sprint — all three
    /// ACs are the same write, mirroring `assignProject`. Rejects a Sprint
    /// that doesn't belong to the Task's *current* Project — this also
    /// correctly rejects any Sprint when the Task is currently Project-less,
    /// since no Sprint's `project.id` can equal `nil`.
    func assignSprint(req: Request) async throws -> TaskResponse {
        guard let task = try await findTask(req: req) else {
            throw Abort(.notFound)
        }
        let payload = try req.content.decode(AssignTaskSprintRequest.self)
        if let sprintID = payload.sprintID {
            guard let sprint = try await Sprint.find(sprintID, on: req.db) else {
                throw Abort(.badRequest, reason: "no such Sprint")
            }
            guard sprint.$project.id == task.$project.id else {
                throw Abort(.badRequest, reason: "Sprint does not belong to this Task's Project")
            }
        }
        task.$sprint.id = payload.sprintID
        try await task.save(on: req.db)
        return try TaskResponse(task)
    }

    /// Attach, change, or remove (`dueDate: null`) a Task's Deadline — all
    /// three ACs are the same write, mirroring `assignProject`.
    func setDeadline(req: Request) async throws -> TaskResponse {
        guard let task = try await findTask(req: req) else {
            throw Abort(.notFound)
        }
        let payload = try req.content.decode(SetTaskDeadlineRequest.self)
        task.dueDate = payload.dueDate
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
