import Fluent
import Vapor

/// A container of related Tasks with its own lifecycle (`CONTEXT.md`). May
/// carry a Deadline (ticket #5) — modeled as a plain nullable field, same
/// tradeoff as `PCCTask.dueDate`. May optionally belong to a Client (ticket
/// #17) or to a Course (ticket #88, ADR-0011) — never both: the two foreign
/// keys are independently optional (parent-less is a valid, ordinary state,
/// not an error case), and the exclusivity is enforced at write time by
/// `setParent`, exactly the way `PCCTask.setContainer` enforces Task's own
/// Project-xor-Course rule.
final class Project: Model, @unchecked Sendable {
    static let schema = "projects"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    @OptionalField(key: "due_date")
    var dueDate: Date?

    @OptionalParent(key: "client_id")
    var client: PCCClient?

    /// The Course (`CONTEXT.md`) this Project belongs to, if any — the
    /// alternate parent to `client` (ADR-0011), for coursework that has the
    /// Project shape (e.g. a semester group assignment). Cleared whenever
    /// the Project is assigned a Client, and vice versa (`setParent`).
    @OptionalParent(key: "course_id")
    var course: Course?

    init() {}

    init(
        id: UUID? = nil,
        name: String,
        dueDate: Date? = nil,
        clientID: UUID? = nil,
        courseID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.dueDate = dueDate
        // Routed through `setParent` rather than assigning both foreign keys
        // directly, so a both-parents Project can't be constructed in the
        // first place — ADR-0011 asks for the exclusivity to be enforced
        // rather than conventional, and the two controller endpoints aren't
        // the only way a Project gets made (migrations, tests, future
        // services). `preconditionFailure` rather than a thrown error: this
        // is a programming mistake at a call site, not owner input, which
        // reaches the model only after `ProjectController` has already
        // resolved it to one parent.
        switch (clientID, courseID) {
        case (let clientID?, nil): setParent(.client(clientID))
        case (nil, let courseID?): setParent(.course(courseID))
        case (nil, nil): setParent(.none)
        case (.some, .some):
            preconditionFailure("a Project belongs to a Client or a Course, never both (ADR-0011)")
        }
    }

    /// `client`/`course` read together as one `ProjectParent` — see its doc
    /// comment for why they're bundled.
    var parent: ProjectParent {
        if let clientID = $client.id { return .client(clientID) }
        if let courseID = $course.id { return .course(courseID) }
        return .none
    }

    /// Moves this Project to `parent`, clearing whichever of Client/Course
    /// isn't the new one (ADR-0011's exclusivity) — the single place
    /// `ProjectController.setClient`/`setCourse` both funnel through,
    /// mirroring `PCCTask.setContainer`.
    func setParent(_ parent: ProjectParent) {
        switch parent {
        case .client(let id):
            $client.id = id
            $course.id = nil
        case .course(let id):
            $client.id = nil
            $course.id = id
        case .none:
            $client.id = nil
            $course.id = nil
        }
    }
}
