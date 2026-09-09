import Testing

@testable import App

/// Covers `SchoolFigures` — General Weighted Average and Units Earned
/// (issue #92) as pure arithmetic, with no HTTP or database involved, so
/// each edge case of the two rules is stated on its own rather than through
/// a request that also exercises routing and persistence.
///
/// Top-level rather than nested in `AppTestSuite`: nothing here touches the
/// shared Postgres test database, so it has no reason to serialize behind
/// the suites that do.
@Suite("SchoolFigures")
struct SchoolFiguresTests {
    private func mark(_ grade: Grade?, _ units: Double) -> SchoolFigures.Contribution {
        SchoolFigures.Contribution(grade: grade, units: units)
    }

    @Test("GWA weights each mark by its units, not by subject count")
    func gwaIsUnitWeighted() {
        // (1.00×5 + 3.00×1) ÷ 6 = 1.333…, not the 2.00 a plain mean gives.
        let gwa = SchoolFigures.generalWeightedAverage(over: [mark(.one, 5), mark(.three, 1)])
        #expect(gwa != nil)
        #expect(abs((gwa ?? 0) - 8.0 / 6.0) < 0.000_001)
    }

    @Test("half-unit subjects weigh half as much")
    func gwaHandlesFractionalUnits() {
        // (2.00×1.5 + 3.00×0.5) ÷ 2 = 2.25.
        let gwa = SchoolFigures.generalWeightedAverage(over: [mark(.two, 1.5), mark(.three, 0.5)])
        #expect(abs((gwa ?? 0) - 2.25) < 0.000_001)
    }

    @Test("a failure drags GWA down but earns no units")
    func failureCountsTowardGWAOnly() {
        let marks = [mark(.one, 3), mark(.five, 3)]
        #expect(abs((SchoolFigures.generalWeightedAverage(over: marks) ?? 0) - 3.0) < 0.000_001)
        #expect(SchoolFigures.unitsEarned(over: marks) == 3)
    }

    @Test("INC and DRP count toward neither figure")
    func nonNumericMarksCountTowardNeither() {
        let marks = [mark(.two, 3), mark(.incomplete, 3), mark(.dropped, 3)]
        // The average is the graded subject's own mark — the other two
        // aren't in the numerator or the denominator.
        #expect(abs((SchoolFigures.generalWeightedAverage(over: marks) ?? 0) - 2.0) < 0.000_001)
        #expect(SchoolFigures.unitsEarned(over: marks) == 3)
    }

    @Test("an ungraded ongoing subject counts toward neither figure")
    func ungradedCountsTowardNeither() {
        let marks = [mark(.oneFifty, 3), mark(nil, 3)]
        #expect(abs((SchoolFigures.generalWeightedAverage(over: marks) ?? 0) - 1.5) < 0.000_001)
        #expect(SchoolFigures.unitsEarned(over: marks) == 3)
    }

    @Test("GWA over nothing is absent, not zero")
    func gwaOverNothingIsNil() {
        #expect(SchoolFigures.generalWeightedAverage(over: []) == nil)
        #expect(SchoolFigures.generalWeightedAverage(over: [mark(nil, 3), mark(.dropped, 3)]) == nil)
        // Units Earned differs deliberately: no units passed really is zero.
        #expect(SchoolFigures.unitsEarned(over: []) == 0)
    }

    @Test("3.00 passes and earns its units")
    func passingMarkEarnsUnits() {
        #expect(Grade.three.earnsUnits)
        #expect(!Grade.five.earnsUnits)
        #expect(!Grade.incomplete.earnsUnits)
        #expect(!Grade.dropped.earnsUnits)
        #expect(SchoolFigures.unitsEarned(over: [mark(.three, 2)]) == 2)
    }

    @Test("INC reads as ongoing, DRP does not")
    func incompleteIsOngoing() {
        #expect(Grade.incomplete.isOngoing)
        #expect(!Grade.dropped.isOngoing)
        #expect(!Grade.one.isOngoing)
    }

    @Test("both retakes of a subject count, with no link between them")
    func retakesBothCount() {
        // The transcript shows both attempts, so both weigh in: a 5.00 and a
        // later 2.00 in the same 3-unit subject average to 3.50, and only
        // the passing attempt's units are earned.
        let marks = [mark(.five, 3), mark(.two, 3)]
        #expect(abs((SchoolFigures.generalWeightedAverage(over: marks) ?? 0) - 3.5) < 0.000_001)
        #expect(SchoolFigures.unitsEarned(over: marks) == 3)
    }

    @Test("every ladder mark parses to its printed value")
    func numericValuesMatchRawValues() {
        #expect(Grade.one.numericValue == 1.00)
        #expect(Grade.oneTwentyFive.numericValue == 1.25)
        #expect(Grade.twoSeventyFive.numericValue == 2.75)
        #expect(Grade.five.numericValue == 5.00)
        #expect(Grade.incomplete.numericValue == nil)
        #expect(Grade.dropped.numericValue == nil)
        // Ten numeric marks plus INC and DRP — the whole legal ladder.
        #expect(Grade.allCases.filter { $0.countsTowardGWA }.count == 10)
        #expect(Grade.allCases.count == 12)
    }
}
