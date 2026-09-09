import Foundation
import Testing

@testable import PCCUI

/// Covers `SchoolSummary`'s own formatting and the client-side `Grade`
/// mirror (issue #92). The GWA arithmetic itself is the backend's
/// (`SchoolFiguresTests`) — what's tested here is how those figures are read
/// out, since the tile's "no marks yet" and "perfect score" cases look
/// dangerously alike on a scale where low is good.
@Suite("SchoolSummary")
struct SchoolSummaryTests {
    @Test("a missing GWA reads as a dash, never as zero")
    func missingGWAIsADash() {
        #expect(SchoolSummary.formatted(nil) == "—")
        // Zero would be off the bottom of a scale whose best mark is 1.00 —
        // it must never stand in for "nothing counted yet".
        #expect(SchoolSummary.formatted(0) == "0.00")
    }

    @Test("a GWA prints to two decimals, like the school's own scale")
    func gwaPrintsTwoDecimals() {
        #expect(SchoolSummary.formatted(1.0) == "1.00")
        #expect(SchoolSummary.formatted(8.0 / 6.0) == "1.33")
        #expect(SchoolSummary.formatted(5.0 / 3.0) == "1.67")
    }

    @Test("units print bare when whole and to one decimal when halved")
    func unitsPrintWithoutNeedlessDecimals() {
        #expect(PCCUnits.text(0) == "0")
        #expect(PCCUnits.text(21) == "21")
        #expect(PCCUnits.text(21.5) == "21.5")
    }

    @Test("the client's Grade ladder mirrors the backend's")
    func gradeLadderMatchesBackend() {
        #expect(Grade.allCases.count == 12)
        #expect(Grade.allCases.compactMap(\.numericValue).count == 10)
        #expect(Grade.one.numericValue == 1.00)
        #expect(Grade.five.numericValue == 5.00)
        #expect(Grade.incomplete.numericValue == nil)
        #expect(Grade.dropped.numericValue == nil)
        #expect(Grade.passingMark == 3.00)
        // Only INC keeps the subject reading as ongoing; DRP ends it, and
        // the card says so rather than printing INC like a final mark.
        #expect(Grade.incomplete.isOngoing)
        #expect(!Grade.dropped.isOngoing)
        #expect(Grade.incomplete.cardLabel == "INC · ONGOING")
        #expect(Grade.dropped.cardLabel == "DRP")
        #expect(Grade.oneSeventyFive.cardLabel == "1.75")
    }

    @Test("a mark decodes from the string the school prints")
    func gradeDecodesFromPrintedMark() throws {
        let decoded = try JSONDecoder().decode([Grade].self, from: Data(#"["1.25","INC"]"#.utf8))
        #expect(decoded == [.oneTwentyFive, .incomplete])
    }

    @Test("a summary decodes the backend's nullable GWA figures")
    func summaryDecodesNullFigures() throws {
        let json = #"{"termID":null,"termGWA":null,"cumulativeGWA":1.5,"unitsEarned":18}"#
        let summary = try JSONDecoder().decode(SchoolSummary.self, from: Data(json.utf8))
        #expect(summary.termGWA == nil)
        #expect(summary.cumulativeGWA == 1.5)
        #expect(summary.unitsEarned == 18)
    }
}
