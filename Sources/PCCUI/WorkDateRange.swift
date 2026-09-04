import Foundation

/// The three window sizes the Work screen's range stepper offers (issue
/// #89) — a stepper, not `FormControls.swift`'s `DateRangeSelection` preset
/// menu: this screen's range moves backwards and forwards one window at a
/// time ("last week", "the week before that"), which a fixed preset list
/// like "Last 7 Days"/"Last Month" can't express.
public enum WorkRangeUnit: String, CaseIterable, Identifiable, Sendable {
    case day, week, month

    public var id: String { rawValue }

    /// The stepper segment's label — "Today" rather than "Day", since the
    /// segment names the *current* window, which is what it selects.
    public var title: String {
        switch self {
        case .day: return "Today"
        case .week: return "Week"
        case .month: return "Month"
        }
    }
}

/// Which window of time the Work screen is showing: a unit, plus how many
/// whole units back from the present the stepper has walked (`0` is the
/// current one, `-1` the previous, `+1` a future one the arrows allow so a
/// step back is always reversible).
///
/// A value type with pure resolution rather than two stored `Date`s, so
/// stepping is `offset -= 1` and the calendar math lives in exactly one
/// place — `WorkDateRangeTests` covers it without a view.
public struct WorkDateRange: Equatable, Sendable {
    public var unit: WorkRangeUnit
    public var offset: Int

    public init(unit: WorkRangeUnit = .week, offset: Int = 0) {
        self.unit = unit
        self.offset = offset
    }

    /// Moves one whole window back (`-1`) or forward (`+1`).
    public mutating func step(_ delta: Int) {
        offset += delta
    }

    /// The half-open `[start, end)` this range covers, matching the
    /// backend's own Work Hours range convention
    /// (`WorkHoursController.validatedRange`). Always whole calendar
    /// windows — a week runs Monday 00:00 to the next Monday 00:00 even when
    /// `offset` is `0` and half of it is still in the future, so the
    /// per-day bar chart has a fixed number of bars that don't shuffle as
    /// the day goes on.
    ///
    /// Monday-anchored regardless of the current locale's `firstWeekday`,
    /// the same explicit calculation `DateRangeSelection.resolvedRange`
    /// makes for its own `.thisWeek` (weekday `1` is Sunday through `7`
    /// Saturday, so days-since-Monday is `weekday - 2`, except Sunday,
    /// which needs `6`).
    public func resolved(
        calendar: Calendar = .current, reference: Date = Date()
    ) -> (start: Date, end: Date) {
        let today = calendar.startOfDay(for: reference)
        switch unit {
        case .day:
            let start = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            return (start, calendar.date(byAdding: .day, value: 1, to: start) ?? start)
        case .week:
            let weekday = calendar.component(.weekday, from: today)
            let daysSinceMonday = weekday == 1 ? 6 : weekday - 2
            let thisMonday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) ?? today
            let start = calendar.date(byAdding: .day, value: 7 * offset, to: thisMonday) ?? thisMonday
            return (start, calendar.date(byAdding: .day, value: 7, to: start) ?? start)
        case .month:
            let thisMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today
            let start = calendar.date(byAdding: .month, value: offset, to: thisMonth) ?? thisMonth
            return (start, calendar.date(byAdding: .month, value: 1, to: start) ?? start)
        }
    }

    /// Every calendar day in the range, start-of-day, in order — one bar of
    /// the Work screen's per-day chart each. Dense: a day with nothing
    /// logged is still a (zero-height) bar, mirroring how the backend's own
    /// `groupBy: day` rollup returns a dense row per day.
    public func days(calendar: Calendar = .current, reference: Date = Date()) -> [Date] {
        let (start, end) = resolved(calendar: calendar, reference: reference)
        var days: [Date] = []
        var current = calendar.startOfDay(for: start)
        while current < end {
            days.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return days
    }

    /// What the stepper shows between its two arrows — "Today"/"Yesterday"
    /// and the plain month name for the common cases, an explicit date
    /// otherwise, so the label answers "which window am I on?" without the
    /// owner counting arrow presses.
    public func title(calendar: Calendar = .current, reference: Date = Date()) -> String {
        let (start, end) = resolved(calendar: calendar, reference: reference)
        switch unit {
        case .day:
            if offset == 0 { return "Today" }
            if offset == -1 { return "Yesterday" }
            return Self.dayFormatter.string(from: start)
        case .week:
            if offset == 0 { return "This Week" }
            if offset == -1 { return "Last Week" }
            // The last day *in* the range, not the exclusive end date.
            let lastDay = calendar.date(byAdding: .day, value: -1, to: end) ?? start
            return DateRangeSelection.formattedRange(start, lastDay)
        case .month:
            if offset == 0 { return "This Month" }
            if offset == -1 { return "Last Month" }
            return Self.monthFormatter.string(from: start)
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
}
