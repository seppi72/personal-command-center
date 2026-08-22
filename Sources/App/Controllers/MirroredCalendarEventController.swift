import Fluent
import Vapor

struct MirroredCalendarEventResponse: Content {
    let id: UUID
    let title: String
    let startDate: Date
    let endDate: Date
    let lastSyncedAt: Date

    init(_ event: MirroredCalendarEvent) throws {
        self.id = try event.requireID()
        self.title = event.title
        self.startDate = event.startDate
        self.endDate = event.endDate
        self.lastSyncedAt = event.lastSyncedAt
    }
}

/// Read-only, per spec #1's schema: only `index` — no create/update/delete
/// routes. `CalendarSyncService.pull` (ticket #7) is the sole writer of
/// `MirroredCalendarEvent` rows; nothing here is owner-editable through the
/// API (user story 22).
struct MirroredCalendarEventController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.grouped("calendar-events").get(use: index)
    }

    func index(req: Request) async throws -> [MirroredCalendarEventResponse] {
        try await MirroredCalendarEvent.query(on: req.db).all().map(MirroredCalendarEventResponse.init)
    }
}
