import Foundation
import Testing

@testable import PCCUI

/// Covers `PCCDuration.stamp(_:)` — the compact "1H 32M" duration-stamp
/// format this package's glass rows and status strips share (issue #70).
/// Was `TimeEntriesViewModelTests`, following the formatter itself out of
/// the deleted `TimeEntriesViewModel` and into `PCCDuration` (issue #89).
@Suite("PCCDuration.stamp")
struct PCCDurationStampTests {
    @Test("zero seconds renders as 0M")
    func zero() {
        #expect(PCCDuration.stamp(0) == "0M")
    }

    @Test("under an hour renders as minutes only")
    func underAnHour() {
        #expect(PCCDuration.stamp(37 * 60) == "37M")
    }

    @Test("exactly an hour renders with a zero-padded minutes component")
    func exactlyAnHour() {
        #expect(PCCDuration.stamp(3600) == "1H 00M")
    }

    @Test("past an hour renders hours and zero-padded minutes")
    func pastAnHour() {
        #expect(PCCDuration.stamp(3600 + 32 * 60) == "1H 32M")
    }

    @Test("multiple hours renders without truncating the hour count")
    func multipleHours() {
        #expect(PCCDuration.stamp(2 * 3600 + 5 * 60) == "2H 05M")
    }

    @Test("a negative duration clamps to 0M rather than going negative")
    func negativeClampsToZero() {
        #expect(PCCDuration.stamp(-120) == "0M")
    }

    @Test("sub-minute remainders are truncated, not rounded")
    func truncatesPartialMinutes() {
        #expect(PCCDuration.stamp(89) == "1M")
    }
}

/// Covers `PCCDuration.compact(_:)` — the quieter lower-case treatment the
/// Work screen's tree rows use, where a zero total is a real, expected
/// reading (a Project with no hours in the selected range still appears —
/// the range filters the numbers, not membership, issue #89).
@Suite("PCCDuration.compact")
struct PCCDurationCompactTests {
    @Test("zero seconds renders as 0m")
    func zero() {
        #expect(PCCDuration.compact(0) == "0m")
    }

    @Test("under an hour renders as minutes only")
    func underAnHour() {
        #expect(PCCDuration.compact(37 * 60) == "37m")
    }

    @Test("past an hour renders hours and unpadded minutes")
    func pastAnHour() {
        #expect(PCCDuration.compact(3600 + 5 * 60) == "1h 5m")
    }

    @Test("a negative duration clamps to 0m rather than going negative")
    func negativeClampsToZero() {
        #expect(PCCDuration.compact(-120) == "0m")
    }
}

/// Covers `PCCDuration.elapsed(_:)` — the ticking, second-resolution readout
/// the Work screen's running-timer chip shows (issue #89), as distinct from
/// the two whole-minute formats above.
@Suite("PCCDuration.elapsed")
struct PCCDurationElapsedTests {
    @Test("under an hour renders as zero-padded minutes and seconds")
    func underAnHour() {
        #expect(PCCDuration.elapsed(2 * 60 + 3) == "02:03")
    }

    @Test("past an hour grows an unpadded hours component")
    func pastAnHour() {
        #expect(PCCDuration.elapsed(3600 + 2 * 60 + 3) == "1:02:03")
    }

    @Test("seconds are shown, not rounded away")
    func showsSeconds() {
        #expect(PCCDuration.elapsed(1) == "00:01")
    }

    @Test("a negative interval clamps to zero rather than going negative")
    func negativeClampsToZero() {
        #expect(PCCDuration.elapsed(-5) == "00:00")
    }
}
