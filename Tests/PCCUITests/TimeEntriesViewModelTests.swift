import Foundation
import Testing

@testable import PCCUI

/// Covers `TimeEntriesViewModel.formattedDuration(_:)` — the compact
/// "1H 32M" duration-stamp format this screen's glass rows share (issue
/// #70). The one piece of pure logic this view model owns, same as
/// `TasksViewModel.isOverdue` is for its own type.
@Suite("TimeEntriesViewModel.formattedDuration")
struct TimeEntriesViewModelTests {
    @Test("zero seconds renders as 0M")
    func zero() {
        #expect(TimeEntriesViewModel.formattedDuration(0) == "0M")
    }

    @Test("under an hour renders as minutes only")
    func underAnHour() {
        #expect(TimeEntriesViewModel.formattedDuration(37 * 60) == "37M")
    }

    @Test("exactly an hour renders with a zero-padded minutes component")
    func exactlyAnHour() {
        #expect(TimeEntriesViewModel.formattedDuration(3600) == "1H 00M")
    }

    @Test("past an hour renders hours and zero-padded minutes")
    func pastAnHour() {
        #expect(TimeEntriesViewModel.formattedDuration(3600 + 32 * 60) == "1H 32M")
    }

    @Test("multiple hours renders without truncating the hour count")
    func multipleHours() {
        #expect(TimeEntriesViewModel.formattedDuration(2 * 3600 + 5 * 60) == "2H 05M")
    }

    @Test("a negative duration clamps to 0M rather than going negative")
    func negativeClampsToZero() {
        #expect(TimeEntriesViewModel.formattedDuration(-120) == "0M")
    }

    @Test("sub-minute remainders are truncated, not rounded")
    func truncatesPartialMinutes() {
        #expect(TimeEntriesViewModel.formattedDuration(89) == "1M")
    }
}
