import Foundation

/// The five dimensions Work Hours (`CONTEXT.md`) can be rolled up by —
/// mirrors the backend's own `WorkHoursGroupBy`
/// (`Sources/App/Controllers/WorkHoursController.swift`). `CaseIterable` so
/// `WorkHoursView`'s `Picker` can enumerate all five without listing them a
/// second time.
public enum WorkHoursGroupBy: String, CaseIterable, Sendable {
    case day, project, client, task, course

    /// The label `WorkHoursView`'s `Picker` shows for this case.
    public var displayName: String {
        switch self {
        case .day: return "Day"
        case .project: return "Project"
        case .client: return "Client"
        case .task: return "Task"
        case .course: return "Course"
        }
    }
}

/// One row of a Work Hours rollup response — either a `day` row (`date`
/// set, `id`/`name` both `nil`) or a `project`/`client`/`task`/`course` row
/// (`id`/`name` set, `date` `nil`), mirroring the backend's own
/// `WorkHoursRow` (`docs/adr/0005-work-hours-rollup-transitive-fold.md`).
/// One client-side type for both shapes rather than five, since a given
/// response only ever contains rows of the one `groupBy` kind that was
/// requested — the caller already knows which fields to expect, and
/// `WorkHoursView` reads whichever of `date`/`name` is non-`nil` to label a
/// row either way.
public struct WorkHoursRow: Decodable, Sendable {
    public let date: Date?
    public let id: UUID?
    public let name: String?
    public let totalSeconds: Double

    private enum CodingKeys: String, CodingKey {
        case date, totalSeconds
        case projectID, projectName
        case clientID, clientName
        case taskID, taskName
        case courseID, courseName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalSeconds = try container.decode(Double.self, forKey: .totalSeconds)
        if let date = try container.decodeIfPresent(Date.self, forKey: .date) {
            self.date = date
            self.id = nil
            self.name = nil
        } else if let id = try container.decodeIfPresent(UUID.self, forKey: .projectID) {
            self.date = nil
            self.id = id
            self.name = try container.decode(String.self, forKey: .projectName)
        } else if let id = try container.decodeIfPresent(UUID.self, forKey: .clientID) {
            self.date = nil
            self.id = id
            self.name = try container.decode(String.self, forKey: .clientName)
        } else if let id = try container.decodeIfPresent(UUID.self, forKey: .taskID) {
            self.date = nil
            self.id = id
            self.name = try container.decode(String.self, forKey: .taskName)
        } else if let id = try container.decodeIfPresent(UUID.self, forKey: .courseID) {
            self.date = nil
            self.id = id
            self.name = try container.decode(String.self, forKey: .courseName)
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .date, in: container, debugDescription: "Unrecognized Work Hours row shape"
            )
        }
    }
}
