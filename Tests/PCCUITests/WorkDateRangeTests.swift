import Foundation
import Testing

@testable import PCCUI

/// Covers `WorkDateRange` — the Work screen's Today/Week/Month stepper
/// (issue #89). Every case passes an explicit `calendar` and `reference`
/// date, so a result never depends on the machine's locale or on when the
/// test happens to run.
@Suite("WorkDateRange")
struct WorkDateRangeTests {
    /// A Gregorian, UTC calendar with an explicit `firstWeekday`, so the
    /// Monday anchoring under test is the range's own doing rather than the
    /// calendar's.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 1  // Sunday — deliberately *not* Monday.
        return calendar
    }

    private func date(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: iso)!
    }

    /// A Wednesday.
    private var wednesday: Date { date("2026-09-02 15:30") }

    @Test("Today resolves to the whole current calendar day")
    func todayIsOneWholeDay() {
        let range = WorkDateRange(unit: .day)
        let (start, end) = range.resolved(calendar: calendar, reference: wednesday)
        #expect(start == date("2026-09-02 00:00"))
        #expect(end == date("2026-09-03 00:00"))
    }

    @Test("stepping back a day moves the window one whole day earlier")
    func dayStepsBack() {
        var range = WorkDateRange(unit: .day)
        range.step(-1)
        let (start, end) = range.resolved(calendar: calendar, reference: wednesday)
        #expect(start == date("2026-09-01 00:00"))
        #expect(end == date("2026-09-02 00:00"))
    }

    @Test("a week is Monday-anchored regardless of the calendar's firstWeekday")
    func weekIsMondayAnchored() {
        let range = WorkDateRange(unit: .week)
        let (start, end) = range.resolved(calendar: calendar, reference: wednesday)
        #expect(start == date("2026-08-31 00:00"))
        #expect(end == date("2026-09-07 00:00"))
    }

    @Test("a Sunday still belongs to the week that started the Monday before it")
    func sundayBelongsToThePrecedingMonday() {
        let range = WorkDateRange(unit: .week)
        let (start, _) = range.resolved(calendar: calendar, reference: date("2026-09-06 12:00"))
        #expect(start == date("2026-08-31 00:00"))
    }

    @Test("stepping back a week moves the window seven whole days earlier")
    func weekStepsBack() {
        var range = WorkDateRange(unit: .week)
        range.step(-1)
        let (start, end) = range.resolved(calendar: calendar, reference: wednesday)
        #expect(start == date("2026-08-24 00:00"))
        #expect(end == date("2026-08-31 00:00"))
    }

    @Test("a month runs from the first of the month to the first of the next")
    func monthIsWholeCalendarMonth() {
        let range = WorkDateRange(unit: .month)
        let (start, end) = range.resolved(calendar: calendar, reference: wednesday)
        #expect(start == date("2026-09-01 00:00"))
        #expect(end == date("2026-10-01 00:00"))
    }

    @Test("stepping back a month lands on the previous month, whatever its length")
    func monthStepsBack() {
        var range = WorkDateRange(unit: .month)
        range.step(-1)
        let (start, end) = range.resolved(calendar: calendar, reference: wednesday)
        #expect(start == date("2026-08-01 00:00"))
        #expect(end == date("2026-09-01 00:00"))
    }

    @Test("a week is seven dense bars, one per day, in order")
    func weekHasSevenDenseDays() {
        let days = WorkDateRange(unit: .week).days(calendar: calendar, reference: wednesday)
        #expect(days.count == 7)
        #expect(days.first == date("2026-08-31 00:00"))
        #expect(days.last == date("2026-09-06 00:00"))
    }

    @Test("a whole future window is reachable, so a step back is always reversible")
    func forwardStepIsAllowed() {
        var range = WorkDateRange(unit: .day)
        range.step(-1)
        range.step(1)
        #expect(range.offset == 0)
        let (start, _) = range.resolved(calendar: calendar, reference: wednesday)
        #expect(start == date("2026-09-02 00:00"))
    }
}
