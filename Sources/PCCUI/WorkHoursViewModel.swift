import Foundation

/// Holds the Work Hours screen's state and talks to the backend through a
/// `WorkHoursAPIClient` — kept separate from `WorkHoursView` so the view
/// stays a thin rendering of this state, mirroring `TimeEntriesViewModel`'s
/// split.
///
/// `ObservableObject` rather than the newer `@Observable` macro, since that
/// macro needs iOS 17/macOS 14 and this package targets iOS 16/macOS 13.
@MainActor
public final class WorkHoursViewModel: ObservableObject {
    @Published public var groupBy: WorkHoursGroupBy
    @Published public var start: Date
    @Published public var end: Date
    @Published public private(set) var rows: [WorkHoursRow] = []
    @Published public var errorMessage: String?
    @Published public private(set) var isLoading = false

    private let client: WorkHoursAPIClient

    /// Defaults (ticket #25): `groupBy = .day`, current week (Monday
    /// through now) — a caller can override either via `start`/`end`, but
    /// nothing in this ticket's scope needs to.
    public init(client: WorkHoursAPIClient, start: Date? = nil, end: Date? = nil) {
        self.client = client
        self.groupBy = .day
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // `Calendar.current.component(.weekday, from:)` is 1 = Sunday ...
        // 7 = Saturday (this package already assumes the Gregorian
        // calendar elsewhere, e.g. `CourseView`'s Term picker) — days
        // since Monday is `weekday - 2`, except Sunday, which needs 6
        // rather than the `-1` that formula would give it.
        let weekday = calendar.component(.weekday, from: today)
        let daysSinceMonday = weekday == 1 ? 6 : weekday - 2
        let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) ?? today
        self.start = start ?? monday
        self.end = end ?? Date()
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            rows = try await client.fetchWorkHours(groupBy: groupBy, start: start, end: end)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load Work Hours: \(error.localizedDescription)"
        }
    }
}
