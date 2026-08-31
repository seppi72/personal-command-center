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
    /// `PCCDateRangeControl` (`FormControls.swift`) reads/writes this
    /// directly — defaults to `.thisWeek`, the same "current week, Monday
    /// through now" default this view model always had, now resolved by
    /// `DateRangeSelection` (`.thisWeek`'s own doc comment carries the
    /// Monday-anchored calculation this file used to duplicate) instead of
    /// computed here.
    @Published public var dateRange = DateRangeSelection(option: .thisWeek)
    @Published public private(set) var rows: [WorkHoursRow] = []
    @Published public var errorMessage: String?
    @Published public private(set) var isLoading = false

    private let client: WorkHoursAPIClient

    public init(client: WorkHoursAPIClient) {
        self.client = client
        self.groupBy = .day
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let range = dateRange.resolvedRange
            rows = try await client.fetchWorkHours(groupBy: groupBy, start: range.start, end: range.end)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load Work Hours: \(error.localizedDescription)"
        }
    }
}
