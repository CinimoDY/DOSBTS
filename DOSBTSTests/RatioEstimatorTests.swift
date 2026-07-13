//
//  RatioEstimatorTests.swift
//  DOSBTSTests
//
//  Pins every threshold and qualification rule in RatioEstimator (DMNC-1297, WP-R1).
//  See docs/plans/2026-07-03-ratio-lab-plan.md § WP-R1 for the source-of-truth matrix.
//

import Foundation
import Testing
@testable import DOSBTSApp

// MARK: - Fixtures

private func makeMeal(carbs: Double?, at timestamp: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> MealEntry {
    MealEntry(timestamp: timestamp, mealDescription: "test", carbsGrams: carbs)
}

private func makeImpact(baseline: Int?, isClean: Bool = true, for mealId: UUID) -> MealImpact {
    MealImpact(
        mealEntryId: mealId,
        baselineGlucose: baseline,
        peakGlucose: 0,
        deltaMgDL: 0,
        timeToPeakMinutes: 0,
        isClean: isClean,
        timestamp: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

/// A candidate meal that qualifies unless one field is overridden to break exactly one rule.
private func makeObservation(
    carbs: Double? = 60,
    baseline: Int? = 120,
    bolus: Double = 5,
    end: Int? = 120,
    minGlucose: Int? = 110,
    isClean: Bool = true
) -> MealObservation {
    let meal = makeMeal(carbs: carbs)
    let impact = makeImpact(baseline: baseline, isClean: isClean, for: meal.id)
    return MealObservation(
        meal: meal,
        impact: impact,
        pairedBolusUnits: bolus,
        endGlucose: end,
        minGlucoseInWindow: minGlucose
    )
}

/// A qualifying meal whose ICR is exactly `ratio` (bolus fixed at 5 U, carbs = ratio × 5).
private func qualifyingMeal(ratio: Double) -> MealObservation {
    makeObservation(carbs: ratio * 5, baseline: 120, bolus: 5, end: 120, minGlucose: 110)
}

/// A TDD day with both basal and bolus (qualifies), splitting `total` in half.
private func day(total: Double) -> TDDDay {
    TDDDay(date: Date(timeIntervalSince1970: 1_700_000_000), basalUnits: total / 2, bolusUnits: total / 2)
}

private func expectClose(_ actual: Double?, _ expected: Double, tolerance: Double = 1e-9) {
    #expect(actual != nil)
    if let actual { #expect(abs(actual - expected) < tolerance) }
}

// MARK: - Correction fixtures (empirical ISF — DMNC-1303)

/// A correction impact that qualifies unless one field is overridden to break exactly one
/// gate. Default: 2 U dose, baseline 200, nadir 140 → ISF = (200 − 140) / 2 = 30 mg/dL/U.
private func correctionImpact(
    dose: Double = 2,
    baseline: Int? = 200,
    nadir: Int? = 140,
    confounders: [InsulinConfounder] = [],
    at timestamp: Date = Date(timeIntervalSince1970: 1_700_000_000)
) -> InsulinImpact {
    InsulinImpact.compute(
        for: InsulinDelivery(starts: timestamp, ends: timestamp, units: dose, type: .correctionBolus),
        glucoseAtDose: baseline,
        glucoseAtPeak: nadir,
        peakOffsetMinutes: 90,
        iobAtDose: nil,
        confounders: confounders
    )
}

/// A qualifying correction whose ISF is exactly `isf` (dose 2 U, nadir = baseline − 2·isf).
private func qualifyingCorrection(isf: Double) -> InsulinImpact {
    correctionImpact(dose: 2, baseline: 200, nadir: 200 - Int(isf * 2))
}

// MARK: - TDD rules (500 / 1800)

@Suite("RatioEstimator — TDD rules")
struct RatioEstimatorTDDTests {

    @Test("500 rule: median TDD 50 → ICR 1:10")
    func fiveHundredRule() {
        let evidence = RatioEvidence(tddDays: Array(repeating: day(total: 50), count: 5), mealObservations: [])
        let result = RatioEstimator.estimate(evidence: evidence)
        expectClose(result.averageTDD, 50)
        expectClose(result.fiveHundredRuleICR, 10)
        #expect(result.qualifyingDayCount == 5)
    }

    @Test("1800 rule: median TDD 50 → ISF 36 mg/dL")
    func eighteenHundredRule() {
        let evidence = RatioEvidence(tddDays: Array(repeating: day(total: 50), count: 5), mealObservations: [])
        let result = RatioEstimator.estimate(evidence: evidence)
        expectClose(result.eighteenHundredRuleISFMgDL, 36)
    }

    @Test("Rules are nil below the 5-day gate (4 qualifying days)")
    func belowDayGate() {
        let evidence = RatioEvidence(tddDays: Array(repeating: day(total: 50), count: 4), mealObservations: [])
        let result = RatioEstimator.estimate(evidence: evidence)
        #expect(result.averageTDD == nil)
        #expect(result.fiveHundredRuleICR == nil)
        #expect(result.eighteenHundredRuleISFMgDL == nil)
        #expect(result.qualifyingDayCount == 4)
    }

    @Test("Aggregate is the median, not the mean (skewed fixture)")
    func medianNotMean() {
        // Totals 30/40/50/60/200 → median 50, mean 76. TDD must resist the one huge day.
        let evidence = RatioEvidence(
            tddDays: [day(total: 30), day(total: 40), day(total: 50), day(total: 60), day(total: 200)],
            mealObservations: []
        )
        let result = RatioEstimator.estimate(evidence: evidence)
        expectClose(result.averageTDD, 50)
        expectClose(result.fiveHundredRuleICR, 10)
    }

    @Test("Basal-only day is excluded (logging gap, not a low day)")
    func basalOnlyExcluded() {
        let basalOnly = TDDDay(date: Date(timeIntervalSince1970: 1_700_000_000), basalUnits: 30, bolusUnits: 0)
        let evidence = RatioEvidence(
            tddDays: Array(repeating: day(total: 50), count: 5) + [basalOnly],
            mealObservations: []
        )
        let result = RatioEstimator.estimate(evidence: evidence)
        #expect(result.qualifyingDayCount == 5)
        expectClose(result.averageTDD, 50)
    }

    @Test("Bolus-only day is excluded (logging gap, not a low day)")
    func bolusOnlyExcluded() {
        let bolusOnly = TDDDay(date: Date(timeIntervalSince1970: 1_700_000_000), basalUnits: 0, bolusUnits: 30)
        let evidence = RatioEvidence(
            tddDays: Array(repeating: day(total: 50), count: 5) + [bolusOnly],
            mealObservations: []
        )
        let result = RatioEstimator.estimate(evidence: evidence)
        #expect(result.qualifyingDayCount == 5)
        expectClose(result.averageTDD, 50)
    }
}

// MARK: - Meal exclusion reasons (one test per reason)

@Suite("RatioEstimator — meal exclusion reasons")
struct RatioEstimatorExclusionTests {

    @Test("Qualifying meal yields a ratio and no exclusion")
    func qualifies() {
        let scored = RatioEstimator.score(makeObservation())
        expectClose(scored.ratio, 12) // 60 g / 5 U
        #expect(scored.exclusion == nil)
    }

    @Test("Confounded impact (isClean == false) → .confounded")
    func confounded() {
        #expect(RatioEstimator.score(makeObservation(isClean: false)).exclusion == .confounded)
    }

    @Test("No paired bolus → .noBolus")
    func noBolus() {
        #expect(RatioEstimator.score(makeObservation(bolus: 0)).exclusion == .noBolus)
    }

    @Test("Bolus under 0.5 U → .tinyBolus")
    func tinyBolus() {
        #expect(RatioEstimator.score(makeObservation(bolus: 0.25)).exclusion == .tinyBolus)
    }

    @Test("Meal under 15 g → .smallMeal")
    func smallMeal() {
        #expect(RatioEstimator.score(makeObservation(carbs: 10)).exclusion == .smallMeal)
    }

    @Test("Missing baseline → .noBaseline")
    func noBaseline() {
        #expect(RatioEstimator.score(makeObservation(baseline: nil)).exclusion == .noBaseline)
    }

    @Test("Baseline 65 (low start) → .baselineOutOfRange")
    func baselineLow() {
        #expect(RatioEstimator.score(makeObservation(baseline: 65)).exclusion == .baselineOutOfRange)
    }

    @Test("Baseline 190 (high start) → .baselineOutOfRange")
    func baselineHigh() {
        #expect(RatioEstimator.score(makeObservation(baseline: 190)).exclusion == .baselineOutOfRange)
    }

    @Test("Ended +54 mg/dL from baseline → .didNotReturnToBaseline(54)")
    func didNotReturn() {
        // baseline 120, end 174 → signed delta +54.
        let scored = RatioEstimator.score(makeObservation(baseline: 120, end: 174, minGlucose: 120))
        #expect(scored.exclusion == .didNotReturnToBaseline(deltaMgDL: 54))
    }

    @Test("Hypo 62 in window → .hypoInWindow")
    func hypo() {
        #expect(RatioEstimator.score(makeObservation(minGlucose: 62)).exclusion == .hypoInWindow)
    }

    @Test("A visible hypo wins even when the +2h reading is missing (safety over data-gap)")
    func hypoBeatsMissingEndGlucose() {
        // min 55 proves a low; endGlucose absent. The safety lesson (.hypoInWindow) must survive.
        let scored = RatioEstimator.score(makeObservation(end: nil, minGlucose: 55))
        #expect(scored.exclusion == .hypoInWindow)
    }

    @Test("Ended −40 mg/dL below baseline → .didNotReturnToBaseline(-40) (signed)")
    func endedLow() {
        // baseline 120, end 80, no hypo (min 80) → signed delta −40.
        let scored = RatioEstimator.score(makeObservation(baseline: 120, end: 80, minGlucose: 80))
        #expect(scored.exclusion == .didNotReturnToBaseline(deltaMgDL: -40))
    }

    @Test("Ratio 80 g/U → .implausibleRatio")
    func implausibleHigh() {
        // 80 g / 1 U = 80 g/U, above the 50 g/U clamp.
        #expect(RatioEstimator.score(makeObservation(carbs: 80, bolus: 1)).exclusion == .implausibleRatio)
    }

    @Test("Ratio 1.5 g/U → .implausibleRatio")
    func implausibleLow() {
        // 15 g / 10 U = 1.5 g/U, below the 2 g/U clamp.
        #expect(RatioEstimator.score(makeObservation(carbs: 15, bolus: 10)).exclusion == .implausibleRatio)
    }

    @Test("Missing +2h reading → .insufficientData")
    func missingEndGlucose() {
        #expect(RatioEstimator.score(makeObservation(end: nil)).exclusion == .insufficientData)
    }

    @Test("Missing in-window minimum → .insufficientData")
    func missingMinGlucose() {
        #expect(RatioEstimator.score(makeObservation(minGlucose: nil)).exclusion == .insufficientData)
    }
}

// MARK: - Threshold boundaries + precedence

@Suite("RatioEstimator — boundaries & precedence")
struct RatioEstimatorBoundaryTests {

    private func qualifies(_ obs: MealObservation) -> Bool {
        let scored = RatioEstimator.score(obs)
        return scored.ratio != nil && scored.exclusion == nil
    }

    @Test("Baseline is inclusive at 70 and 180; 69 and 181 are out of range")
    func baselineBoundary() {
        // end == baseline so only the baseline bound is under test (delta 0 passes the return check).
        #expect(qualifies(makeObservation(carbs: 30, baseline: 70, end: 70, minGlucose: 70)))    // ratio 6
        #expect(qualifies(makeObservation(carbs: 30, baseline: 180, end: 180, minGlucose: 90)))  // ratio 6
        #expect(RatioEstimator.score(makeObservation(baseline: 69)).exclusion == .baselineOutOfRange)
        #expect(RatioEstimator.score(makeObservation(baseline: 181)).exclusion == .baselineOutOfRange)
    }

    @Test("Bolus is inclusive at 0.5 U; 0.49 U is a tiny bolus")
    func bolusBoundary() {
        #expect(qualifies(makeObservation(carbs: 15, bolus: 0.5))) // ratio 30
        #expect(RatioEstimator.score(makeObservation(bolus: 0.49)).exclusion == .tinyBolus)
    }

    @Test("Carbs are inclusive at 15 g; 14 g is a small meal")
    func carbsBoundary() {
        #expect(qualifies(makeObservation(carbs: 15))) // ratio 3
        #expect(RatioEstimator.score(makeObservation(carbs: 14)).exclusion == .smallMeal)
    }

    @Test("Hypo threshold is inclusive at 70 (not a hypo); 69 is a hypo")
    func hypoBoundary() {
        #expect(qualifies(makeObservation(minGlucose: 70)))
        #expect(RatioEstimator.score(makeObservation(minGlucose: 69)).exclusion == .hypoInWindow)
    }

    @Test("Return tolerance is inclusive at ±30; ±31 fails")
    func returnBoundary() {
        #expect(qualifies(makeObservation(baseline: 120, end: 150, minGlucose: 120)))          // delta +30
        #expect(RatioEstimator.score(makeObservation(baseline: 120, end: 151, minGlucose: 120)).exclusion
            == .didNotReturnToBaseline(deltaMgDL: 31))
    }

    @Test("Ratio clamp is inclusive at 2 and 50 g/U")
    func ratioBoundary() {
        #expect(qualifies(makeObservation(carbs: 30, bolus: 15)))  // ratio 2
        #expect(qualifies(makeObservation(carbs: 100, bolus: 2)))  // ratio 50
    }

    @Test("Precedence follows the plan's criterion order (confounded → baseline → bolus)")
    func precedence() {
        // A confounded meal that ALSO has no bolus and a bad baseline still surfaces .confounded (criterion 1).
        #expect(RatioEstimator.score(makeObservation(baseline: 65, bolus: 0, isClean: false)).exclusion == .confounded)
        // A clean meal that has both a bad baseline (crit 2) and no bolus (crit 3) surfaces the baseline (crit 2).
        #expect(RatioEstimator.score(makeObservation(baseline: 65, bolus: 0)).exclusion == .baselineOutOfRange)
    }
}

// MARK: - Empirical ICR aggregation

@Suite("RatioEstimator — empirical aggregation")
struct RatioEstimatorAggregationTests {

    @Test("Median and P25–P75 spread pinned exactly (ratios 8/10/12/14/16)")
    func medianAndSpread() {
        let evidence = RatioEvidence(
            tddDays: [],
            mealObservations: [8, 10, 12, 14, 16].map { qualifyingMeal(ratio: $0) }
        )
        let result = RatioEstimator.estimate(evidence: evidence)
        expectClose(result.empiricalICR, 12)
        #expect(result.empiricalICRSpread != nil)
        if let spread = result.empiricalICRSpread {
            expectClose(spread.lowerBound, 10)
            expectClose(spread.upperBound, 14)
        }
    }

    @Test("Four qualifying meals → nil (below the 5-meal gate)")
    func belowMealGate() {
        let evidence = RatioEvidence(
            tddDays: [],
            mealObservations: [8, 10, 12, 14].map { qualifyingMeal(ratio: $0) }
        )
        let result = RatioEstimator.estimate(evidence: evidence)
        #expect(result.empiricalICR == nil)
        #expect(result.empiricalICRSpread == nil)
    }

    @Test("Five qualifying meals → value (gate met)")
    func atMealGate() {
        let evidence = RatioEvidence(
            tddDays: [],
            mealObservations: [10, 10, 10, 10, 10].map { qualifyingMeal(ratio: $0) }
        )
        let result = RatioEstimator.estimate(evidence: evidence)
        expectClose(result.empiricalICR, 10)
    }

    @Test("Excluded meals don't count toward the gate")
    func excludedDoNotCount() {
        // Four qualifiers plus one no-bolus meal → still below the 5-meal gate.
        let evidence = RatioEvidence(
            tddDays: [],
            mealObservations: [10, 10, 10, 10].map { qualifyingMeal(ratio: $0) } + [makeObservation(bolus: 0)]
        )
        let result = RatioEstimator.estimate(evidence: evidence)
        #expect(result.empiricalICR == nil)
        #expect(result.scoredObservations.count == 5) // all candidates still surfaced
    }
}

// MARK: - Bolus pairing helper

@Suite("RatioEstimator — bolus pairing")
struct RatioEstimatorPairingTests {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ minutes: Int) -> Date { base.addingTimeInterval(TimeInterval(minutes * 60)) }

    @Test("Meal/snack boluses at −10 and +12 min are summed; +20 min ignored")
    func pairingWindow() {
        let deliveries = [
            InsulinDelivery(starts: at(-10), ends: at(-10), units: 3, type: .mealBolus),
            InsulinDelivery(starts: at(12), ends: at(12), units: 2, type: .snackBolus),
            InsulinDelivery(starts: at(20), ends: at(20), units: 1, type: .mealBolus), // outside ±15
        ]
        expectClose(RatioEstimator.pairedBolusUnits(mealTimestamp: base, deliveries: deliveries), 5)
    }

    @Test("Correction and basal deliveries are not paired")
    func typesExcluded() {
        let deliveries = [
            InsulinDelivery(starts: at(5), ends: at(5), units: 4, type: .correctionBolus),
            InsulinDelivery(starts: at(-5), ends: at(-5), units: 10, type: .basal),
        ]
        expectClose(RatioEstimator.pairedBolusUnits(mealTimestamp: base, deliveries: deliveries), 0)
    }
}

// MARK: - endGlucose / minGlucose selection helpers

@Suite("RatioEstimator — glucose window selection")
struct RatioEstimatorGlucoseWindowTests {

    private let base = Date(timeIntervalSince1970: 1_700_000_000).toRounded(on: 1, .minute)
    private func reading(_ minutes: Int, _ value: Int) -> SensorGlucose {
        SensorGlucose(timestamp: base.addingTimeInterval(TimeInterval(minutes * 60)), rawGlucoseValue: value, intGlucoseValue: value)
    }

    @Test("endGlucose picks the reading nearest +120 min (+108 vs +122 → +122)")
    func endGlucoseNearest() {
        let readings = [reading(108, 150), reading(122, 130)]
        #expect(RatioEstimator.endGlucose(mealTimestamp: base, readings: readings) == 130)
    }

    @Test("endGlucose is nil when no reading falls in +105..+135")
    func endGlucoseOutOfWindow() {
        let readings = [reading(90, 100), reading(140, 100)]
        #expect(RatioEstimator.endGlucose(mealTimestamp: base, readings: readings) == nil)
    }

    @Test("endGlucose tie (+112 vs +128, both 8 min off) → earlier reading wins")
    func endGlucoseTieBreak() {
        let readings = [reading(112, 111), reading(128, 128)]
        #expect(RatioEstimator.endGlucose(mealTimestamp: base, readings: readings) == 111)
    }

    @Test("minGlucoseInWindow returns the minimum in [t, t+2h]; a +150 reading is out of window")
    func minGlucose() {
        let readings = [reading(30, 110), reading(60, 62), reading(90, 130), reading(150, 50)]
        #expect(RatioEstimator.minGlucoseInWindow(mealTimestamp: base, readings: readings) == 62)
    }

    @Test("minGlucoseInWindow is nil with no readings in the window")
    func minGlucoseEmpty() {
        #expect(RatioEstimator.minGlucoseInWindow(mealTimestamp: base, readings: [reading(200, 100)]) == nil)
    }
}

// MARK: - TDD day builder

@Suite("RatioEstimator — TDD day builder")
struct RatioEstimatorTDDDayBuilderTests {

    private let calendar = Calendar.current

    private func today() -> Date { calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000)) }
    private func priorDay(_ daysBack: Int) throws -> Date {
        try #require(calendar.date(byAdding: .day, value: -daysBack, to: today()))
    }

    @Test("Partial today is excluded; a complete prior day is bucketed with both basal and bolus")
    func partialTodayExcluded() throws {
        let today = today()
        let yesterday = try priorDay(1)
        let deliveries = [
            InsulinDelivery(starts: yesterday.addingTimeInterval(8 * 3600), ends: yesterday.addingTimeInterval(8 * 3600), units: 25, type: .basal),
            InsulinDelivery(starts: yesterday.addingTimeInterval(12 * 3600), ends: yesterday.addingTimeInterval(12 * 3600), units: 25, type: .mealBolus),
            InsulinDelivery(starts: today.addingTimeInterval(8 * 3600), ends: today.addingTimeInterval(8 * 3600), units: 10, type: .basal), // partial today
        ]
        let days = RatioEstimator.tddDays(from: deliveries, asOf: today.addingTimeInterval(9 * 3600), calendar: calendar)
        #expect(days.count == 1)
        #expect(days.first?.date == yesterday)
        expectClose(days.first?.basalUnits, 25)
        expectClose(days.first?.bolusUnits, 25)
    }

    @Test("A late-night basal is attributed to its own starts date")
    func basalAttributedToStartsDate() throws {
        let today = today()
        let yesterday = try priorDay(1)
        let deliveries = [
            InsulinDelivery(starts: yesterday.addingTimeInterval(23.5 * 3600), ends: yesterday.addingTimeInterval(23.5 * 3600), units: 20, type: .basal),
            InsulinDelivery(starts: yesterday.addingTimeInterval(12 * 3600), ends: yesterday.addingTimeInterval(12 * 3600), units: 6, type: .mealBolus),
        ]
        let days = RatioEstimator.tddDays(from: deliveries, asOf: today.addingTimeInterval(9 * 3600), calendar: calendar)
        #expect(days.count == 1)
        #expect(days.first?.date == yesterday)
        expectClose(days.first?.basalUnits, 20)
    }

    @Test("Deliveries older than the 14-day window are excluded")
    func outsideLookbackExcluded() throws {
        let today = today()
        let old = try priorDay(20)
        let deliveries = [
            InsulinDelivery(starts: old.addingTimeInterval(8 * 3600), ends: old.addingTimeInterval(8 * 3600), units: 25, type: .basal),
            InsulinDelivery(starts: old.addingTimeInterval(12 * 3600), ends: old.addingTimeInterval(12 * 3600), units: 25, type: .mealBolus),
        ]
        let days = RatioEstimator.tddDays(from: deliveries, asOf: today.addingTimeInterval(9 * 3600), calendar: calendar)
        #expect(days.isEmpty)
    }

    @Test("The builder still returns basal-only and bolus-only days (estimate() qualifies them)")
    func basalOnlyAndBolusOnlyDaysReturned() throws {
        let today = today()
        let basalDay = try priorDay(1)
        let bolusDay = try priorDay(2)
        let deliveries = [
            InsulinDelivery(starts: basalDay.addingTimeInterval(8 * 3600), ends: basalDay.addingTimeInterval(8 * 3600), units: 24, type: .basal),
            InsulinDelivery(starts: bolusDay.addingTimeInterval(12 * 3600), ends: bolusDay.addingTimeInterval(12 * 3600), units: 6, type: .mealBolus),
        ]
        let days = RatioEstimator.tddDays(from: deliveries, asOf: today.addingTimeInterval(9 * 3600), calendar: calendar)
        #expect(days.count == 2)
        let basalDayResult = days.first { $0.date == basalDay }
        let bolusDayResult = days.first { $0.date == bolusDay }
        expectClose(basalDayResult?.basalUnits, 24)
        expectClose(basalDayResult?.bolusUnits, 0)
        expectClose(bolusDayResult?.basalUnits, 0)
        expectClose(bolusDayResult?.bolusUnits, 6)
    }
}

// MARK: - Statistics helpers

@Suite("RatioEstimator — statistics")
struct RatioEstimatorStatisticsTests {

    @Test("median resists the skewed value")
    func median() {
        expectClose(RatioEstimator.median([30, 40, 50, 60, 200]), 50)
    }

    @Test("median is nil for an empty sample")
    func medianEmpty() {
        #expect(RatioEstimator.median([]) == nil)
    }

    @Test("P25 / P75 pinned (type-7 interpolation)")
    func percentiles() {
        let sorted = [8.0, 10, 12, 14, 16]
        expectClose(RatioEstimator.percentile(sorted, 0.25), 10)
        expectClose(RatioEstimator.percentile(sorted, 0.5), 12)
        expectClose(RatioEstimator.percentile(sorted, 0.75), 14)
    }
}

// MARK: - Correction exclusion reasons (one test per reason)

@Suite("RatioEstimator — correction exclusion reasons")
struct RatioEstimatorCorrectionExclusionTests {

    @Test("Qualifying correction yields an ISF and no exclusion")
    func qualifies() {
        let scored = RatioEstimator.scoreCorrection(correctionImpact())
        expectClose(scored.isfMgDLPerUnit, 30) // (200 − 140) / 2 U
        #expect(scored.exclusion == nil)
    }

    @Test("Dose under 0.5 U → .tinyDose")
    func tinyDose() {
        #expect(RatioEstimator.scoreCorrection(correctionImpact(dose: 0.25)).exclusion == .tinyDose)
    }

    @Test("Missing baseline → .noBaseline")
    func noBaseline() {
        #expect(RatioEstimator.scoreCorrection(correctionImpact(baseline: nil)).exclusion == .noBaseline)
    }

    @Test("Baseline 130 (below the correction floor) → .lowStart")
    func lowStart() {
        #expect(RatioEstimator.scoreCorrection(correctionImpact(baseline: 130)).exclusion == .lowStart)
    }

    @Test("Carb-bearing meal in the window → .mealInWindow")
    func mealInWindow() {
        #expect(RatioEstimator.scoreCorrection(correctionImpact(confounders: [.mealInWindow])).exclusion == .mealInWindow)
    }

    @Test("Stacked bolus in the window → .stacked")
    func stacked() {
        #expect(RatioEstimator.scoreCorrection(correctionImpact(confounders: [.stackedBolus(units: 3)])).exclusion == .stacked)
    }

    @Test("Exercise overlapping the window → .exercise")
    func exercise() {
        #expect(RatioEstimator.scoreCorrection(correctionImpact(confounders: [.exerciseInWindow])).exclusion == .exercise)
    }

    @Test("Missing nadir (too little CGM coverage) → .noCGM")
    func noCGM() {
        #expect(RatioEstimator.scoreCorrection(correctionImpact(nadir: nil)).exclusion == .noCGM)
    }

    @Test("Glucose rose (nadir ≥ baseline) → .rose")
    func rose() {
        // baseline 150, nadir 170 → delta +20 (glucose did not fall).
        #expect(RatioEstimator.scoreCorrection(correctionImpact(baseline: 150, nadir: 170)).exclusion == .rose)
    }

    @Test("ISF above the plausible band → .oddISF")
    func oddISFHigh() {
        // dose 0.5, baseline 300, nadir 100 → drop 200, ISF 400 > 200.
        #expect(RatioEstimator.scoreCorrection(correctionImpact(dose: 0.5, baseline: 300, nadir: 100)).exclusion == .oddISF)
    }

    @Test("ISF below the plausible band → .oddISF")
    func oddISFLow() {
        // dose 10, baseline 200, nadir 195 → drop 5, ISF 0.5 < 10.
        #expect(RatioEstimator.scoreCorrection(correctionImpact(dose: 10, baseline: 200, nadir: 195)).exclusion == .oddISF)
    }
}

// MARK: - Correction boundaries + precedence

@Suite("RatioEstimator — correction boundaries & precedence")
struct RatioEstimatorCorrectionBoundaryTests {

    private func qualifies(_ impact: InsulinImpact) -> Bool {
        let scored = RatioEstimator.scoreCorrection(impact)
        return scored.isfMgDLPerUnit != nil && scored.exclusion == nil
    }

    @Test("Dose is inclusive at 0.5 U; 0.49 U is a tiny dose")
    func doseBoundary() {
        // dose 0.5, baseline 200, nadir 140 → drop 60, ISF 120 (in band).
        #expect(qualifies(correctionImpact(dose: 0.5, baseline: 200, nadir: 140)))
        #expect(RatioEstimator.scoreCorrection(correctionImpact(dose: 0.49)).exclusion == .tinyDose)
    }

    @Test("Baseline is inclusive at 140; 139 is a low start")
    func baselineBoundary() {
        // baseline 140, nadir 100 → drop 40, ISF 20.
        #expect(qualifies(correctionImpact(baseline: 140, nadir: 100)))
        #expect(RatioEstimator.scoreCorrection(correctionImpact(baseline: 139)).exclusion == .lowStart)
    }

    @Test("ISF band is inclusive at 10 and 200 mg/dL/U")
    func isfBoundary() {
        // ISF 10: dose 6, baseline 200, nadir 140 → drop 60.
        #expect(qualifies(correctionImpact(dose: 6, baseline: 200, nadir: 140)))
        // ISF 200: dose 0.5, baseline 200, nadir 100 → drop 100.
        #expect(qualifies(correctionImpact(dose: 0.5, baseline: 200, nadir: 100)))
    }

    @Test("Precedence: a tiny dose wins over a missing baseline")
    func precedence() {
        #expect(RatioEstimator.scoreCorrection(correctionImpact(dose: 0.25, baseline: nil)).exclusion == .tinyDose)
    }
}

// MARK: - Empirical ISF aggregation

@Suite("RatioEstimator — empirical ISF aggregation")
struct RatioEstimatorCorrectionAggregationTests {

    @Test("Median and P25–P75 spread pinned exactly (ISFs 20/25/30/35/40)")
    func medianAndSpread() {
        let evidence = RatioEvidence(
            tddDays: [],
            mealObservations: [],
            correctionImpacts: [20, 25, 30, 35, 40].map { qualifyingCorrection(isf: $0) }
        )
        let result = RatioEstimator.estimate(evidence: evidence)
        expectClose(result.empiricalISFMgDL, 30)
        #expect(result.empiricalISFSpread != nil)
        if let spread = result.empiricalISFSpread {
            expectClose(spread.lowerBound, 25)
            expectClose(spread.upperBound, 35)
        }
    }

    @Test("Four qualifying corrections → nil (below the 5-correction gate)")
    func belowGate() {
        let evidence = RatioEvidence(
            tddDays: [],
            mealObservations: [],
            correctionImpacts: [20, 25, 30, 35].map { qualifyingCorrection(isf: $0) }
        )
        let result = RatioEstimator.estimate(evidence: evidence)
        #expect(result.empiricalISFMgDL == nil)
        #expect(result.empiricalISFSpread == nil)
    }

    @Test("Five qualifying corrections → value (gate met)")
    func atGate() {
        let evidence = RatioEvidence(
            tddDays: [],
            mealObservations: [],
            correctionImpacts: [30, 30, 30, 30, 30].map { qualifyingCorrection(isf: $0) }
        )
        let result = RatioEstimator.estimate(evidence: evidence)
        expectClose(result.empiricalISFMgDL, 30)
    }

    @Test("Excluded corrections don't count toward the gate")
    func excludedDoNotCount() {
        // Four qualifiers plus one no-baseline correction → still below the 5-correction gate.
        let evidence = RatioEvidence(
            tddDays: [],
            mealObservations: [],
            correctionImpacts: [30, 30, 30, 30].map { qualifyingCorrection(isf: $0) } + [correctionImpact(baseline: nil)]
        )
        let result = RatioEstimator.estimate(evidence: evidence)
        #expect(result.empiricalISFMgDL == nil)
        #expect(result.scoredCorrections.count == 5) // all candidates still surfaced
    }
}
