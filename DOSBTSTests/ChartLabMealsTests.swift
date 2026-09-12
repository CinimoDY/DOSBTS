//
//  ChartLabMealsTests.swift
//  DOSBTSTests
//
//  Chart Lab P2 (DMNC-1501 / DMNC-1500): the anchor-agnostic `ResponseKernel`,
//  the meal-response builder behind the graded ribbons, the residual detector,
//  and the derived regime bands. Everything here is pure — no view
//  instantiation, no GRDB, no store.
//

import Foundation
import Testing
@testable import DOSBTSApp

// MARK: - Shared helpers

// Copies of the file-private helpers in DirectReducerTests.swift (they are
// file-private there, so every test file carries its own pair).
// `makeTestDefaults()` itself is target-wide.
private func makeState() -> AppState {
    AppState(defaults: makeTestDefaults())
}

private func reduce(_ state: inout DirectState, _ action: DirectAction) {
    directReducer(state: &state, action: action)
}

/// Fixed clock for every fixture below — 12:00 on a date with no DST edge.
private let t0 = Date(timeIntervalSince1970: 1_757_678_400) // 2025-09-12 12:00 UTC

private func at(_ minutes: Double) -> Date {
    t0.addingTimeInterval(minutes * 60)
}

private func reading(_ minutes: Double, _ value: Int) -> SensorGlucose {
    SensorGlucose(timestamp: at(minutes), rawGlucoseValue: value, intGlucoseValue: value)
}

private func meal(_ minutes: Double, carbs: Double?) -> MealEntry {
    MealEntry(timestamp: at(minutes), mealDescription: "fixture", carbsGrams: carbs)
}

private func bolus(_ minutes: Double, units: Double, type: InsulinType = .mealBolus) -> InsulinDelivery {
    InsulinDelivery(starts: at(minutes), ends: at(minutes), units: units, type: type)
}

private func workout(from: Double, to: Double) -> ExerciseEntry {
    ExerciseEntry(
        startTime: at(from),
        endTime: at(to),
        activityType: "running",
        durationMinutes: to - from,
        activeCalories: nil,
        source: nil
    )
}

private func note(_ minutes: Double, tag: JournalNoteTag?, text: String = "fixture") -> JournalNote {
    JournalNote(timestamp: at(minutes), text: text, tag: tag)
}

// MARK: - ResponseWindow kernel

@Suite("ResponseWindow kernel")
struct ResponseWindowKernelTests {
    @Test("the meal window is 15 min of lead, 2 h of lag, summarised by its maximum")
    func mealWindowShape() {
        let window = ResponseWindow.meal(at: t0)
        #expect(window.anchor == t0)
        #expect(window.lead == 15 * 60)
        #expect(window.lag == 2 * 60 * 60)
        #expect(window.summary == .extremum(.max))
    }

    @Test("baseline is the LAST reading before the anchor inside the lead")
    func baselineIsLastInLead() {
        let readings = [
            reading(-40, 90),   // outside the 15-minute lead
            reading(-12, 100),
            reading(-5, 110),   // this one
            reading(5, 130),
        ]
        let summary = ResponseKernel.summarize(.meal(at: t0), readings: readings, now: at(180))
        #expect(summary.baseline == 110)
    }

    @Test("delta is extremum minus baseline")
    func deltaFromBaseline() {
        let readings = [reading(-5, 100), reading(30, 154), reading(60, 140)]
        let summary = ResponseKernel.summarize(.meal(at: t0), readings: readings, now: at(180))
        #expect(summary.extremum == 154)
        #expect(summary.delta == 54)
        #expect(summary.timeToExtremumMinutes == 30)
    }

    @Test("with no baseline in the lead the first in-window reading is the reference")
    func firstInWindowFallback() {
        let readings = [reading(-40, 200), reading(0, 100), reading(45, 128)]
        let summary = ResponseKernel.summarize(.meal(at: t0), readings: readings, now: at(180))
        #expect(summary.baseline == nil)
        #expect(summary.delta == 28)
    }

    @Test("n counts only readings inside the window")
    func nCountsInWindowOnly() {
        let readings = [
            reading(-20, 100), reading(-5, 100),   // lead, not window
            reading(0, 100), reading(30, 120), reading(115, 110),
            reading(130, 105),                      // past +2 h
        ]
        let summary = ResponseKernel.summarize(.meal(at: t0), readings: readings, now: at(300))
        #expect(summary.n == 3)
    }

    @Test("three readings is low confidence; four is not")
    func lowConfidenceThreshold() {
        let three = [reading(-5, 100), reading(5, 110), reading(10, 120), reading(15, 130)]
        // 3 in-window readings (the -5 one is the baseline, not in the window).
        #expect(ResponseKernel.summarize(.meal(at: t0), readings: three, now: at(300)).n == 3)
        #expect(ResponseKernel.summarize(.meal(at: t0), readings: three, now: at(300)).isLowConfidence)

        let four = three + [reading(20, 125)]
        #expect(ResponseKernel.summarize(.meal(at: t0), readings: four, now: at(300)).n == 4)
        #expect(ResponseKernel.summarize(.meal(at: t0), readings: four, now: at(300)).isLowConfidence == false)
    }

    @Test("an empty window is not 'low confidence' — it is no measurement at all")
    func emptyWindowIsNotLowConfidence() {
        let summary = ResponseKernel.summarize(.meal(at: t0), readings: [reading(-5, 100)], now: at(300))
        #expect(summary.n == 0)
        #expect(summary.delta == nil)
        #expect(summary.isLowConfidence == false)
    }

    @Test("an in-progress window ends at now")
    func inProgressEndsAtNow() {
        let now = at(38)
        let summary = ResponseKernel.summarize(.meal(at: t0), readings: [reading(10, 120)], now: now)
        #expect(summary.isInProgress)
        #expect(summary.end == now)
    }

    @Test("a completed window ends at anchor + lag")
    func completedEndsAtLag() {
        let summary = ResponseKernel.summarize(.meal(at: t0), readings: [reading(10, 120)], now: at(300))
        #expect(summary.isInProgress == false)
        #expect(summary.end == t0.addingTimeInterval(2 * 60 * 60))
    }

    @Test("a .min window summarises by its minimum — the shape exercise will use")
    func minimumSummary() {
        let window = ResponseWindow(
            anchor: t0,
            lead: 15 * 60,
            lag: 3 * 60 * 60,
            summary: .extremum(.min)
        )
        let readings = [reading(-5, 140), reading(30, 120), reading(60, 96), reading(120, 130)]
        let summary = ResponseKernel.summarize(window, readings: readings, now: at(400))
        #expect(summary.extremum == 96)
        #expect(summary.delta == -44)
        #expect(summary.timeToExtremumMinutes == 60)
    }

    @Test("a .slope window reads the window's LAST value, not its extremum")
    func slopeSummary() {
        let window = ResponseWindow(anchor: t0, lead: 15 * 60, lag: 4 * 60 * 60, summary: .slope)
        let readings = [reading(-5, 100), reading(30, 180), reading(200, 120)]
        let summary = ResponseKernel.summarize(window, readings: readings, now: at(500))
        #expect(summary.extremum == 120)
        #expect(summary.delta == 20)
        #expect(summary.timeToExtremumMinutes == 200)
    }
}

// MARK: - computeMealOverlayDelta equality (the refactor must not move a number)

@Suite("Meal overlay delta parity")
struct MealOverlayDeltaParityTests {
    /// The algorithm exactly as `MealOverlayLogic.swift` carried it before the
    /// kernel refactor (main @ 9d1cafec, `:31-67`). The shipping function now
    /// delegates to `ResponseKernel`; this is the oracle it must still match.
    private func legacyDelta(
        meal: MealEntry,
        isInProgress: Bool,
        sensorGlucoseValues: [SensorGlucose]
    ) -> (delta: Int?, isLowConfidence: Bool) {
        let windowEnd = isInProgress ? Date() : meal.timestamp.addingTimeInterval(2 * 60 * 60)

        let readings = sensorGlucoseValues.filter { glucose in
            glucose.timestamp >= meal.timestamp && glucose.timestamp <= windowEnd
        }

        guard !readings.isEmpty else { return (nil, false) }

        let baselineStart = meal.timestamp.addingTimeInterval(-15 * 60)
        let baseline = sensorGlucoseValues
            .filter { $0.timestamp >= baselineStart && $0.timestamp < meal.timestamp }
            .last

        let referenceGlucose: Int
        if let baseline {
            referenceGlucose = baseline.glucoseValue
        } else if let first = readings.first {
            referenceGlucose = first.glucoseValue
        } else {
            return (nil, false)
        }

        guard let peak = readings.max(by: { $0.glucoseValue < $1.glucoseValue }) else {
            return (nil, false)
        }
        return (peak.glucoseValue - referenceGlucose, readings.count < 4)
    }

    /// Deterministic LCG so a failure is reproducible.
    private struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    @Test("20 randomised fixtures return the same delta and confidence as the pre-refactor code")
    func randomisedParity() {
        var rng = Seeded(state: 0xD05B_7500_0000_1501)

        for fixture in 0 ..< 20 {
            // Meals from 3 h ago to 30 min in the future, so both the completed
            // and the in-progress branch are exercised.
            let mealOffset = Double.random(in: -180 ... 30, using: &rng)
            let entry = meal(mealOffset, carbs: Double.random(in: 5 ... 90, using: &rng))

            var readings: [SensorGlucose] = []
            var value = Int.random(in: 70 ... 200, using: &rng)
            // Sparse on purpose: some fixtures land under the 4-reading gate.
            let step = Double([5, 5, 15, 40].randomElement(using: &rng) ?? 5)
            var minute = mealOffset - 45
            while minute <= mealOffset + 180 {
                value = max(60, min(320, value + Int.random(in: -12 ... 18, using: &rng)))
                readings.append(reading(minute, value))
                minute += step
            }

            // Honest in-progress flag, exactly as RootSheetContent computes it.
            let now = Date()
            let mealDate = entry.timestamp
            let shifted = readings.map {
                SensorGlucose(
                    timestamp: $0.timestamp.addingTimeInterval(now.timeIntervalSince(t0)),
                    rawGlucoseValue: $0.rawGlucoseValue,
                    intGlucoseValue: $0.intGlucoseValue
                )
            }
            let shiftedMeal = MealEntry(
                timestamp: mealDate.addingTimeInterval(now.timeIntervalSince(t0)),
                mealDescription: entry.mealDescription,
                carbsGrams: entry.carbsGrams
            )
            let isInProgress = Date().timeIntervalSince(shiftedMeal.timestamp) < 2 * 60 * 60

            let expected = legacyDelta(
                meal: shiftedMeal,
                isInProgress: isInProgress,
                sensorGlucoseValues: shifted
            )
            let actual = computeMealOverlayDelta(
                meal: shiftedMeal,
                isInProgress: isInProgress,
                sensorGlucoseValues: shifted
            )

            #expect(actual.delta == expected.delta, "fixture \(fixture): delta")
            #expect(
                actual.isLowConfidence == expected.isLowConfidence,
                "fixture \(fixture): isLowConfidence"
            )
        }
    }

    @Test("the empty-window early return is preserved (nil delta, NOT low confidence)")
    func emptyWindowParity() {
        let entry = meal(-300, carbs: 40)
        let readings = [reading(-320, 100)]
        let actual = computeMealOverlayDelta(
            meal: entry,
            isInProgress: false,
            sensorGlucoseValues: readings
        )
        #expect(actual.delta == nil)
        #expect(actual.isLowConfidence == false)
    }

    @Test("the delta tier bands are untouched")
    func tierBandsUnchanged() {
        #expect(mealImpactDeltaColor(delta: 29) == AmberTheme.cgaGreen)
        #expect(mealImpactDeltaColor(delta: 30) == AmberTheme.amber)
        #expect(mealImpactDeltaColor(delta: 59) == AmberTheme.amber)
        #expect(mealImpactDeltaColor(delta: 60) == AmberTheme.cgaRed)
    }
}

// MARK: - Carb-sized meal symbols

@Suite("Chart Lab meal sizing")
struct ChartLabSizingTests {
    @Test("an unrecorded carb count draws at the floor")
    func nilCarbsIsFloor() {
        #expect(ChartLabSizing.mealSymbolSize(carbs: nil) == 40)
        #expect(ChartLabSizing.mealSymbolSize(carbs: 0) == 40)
    }

    @Test("area is linear in carbs — 10 g lands at 76 pt²")
    func linearInArea() {
        #expect(ChartLabSizing.mealSymbolSize(carbs: 10) == 76)
    }

    @Test("the ceiling is 100 g / 400 pt², and a bigger plate does not grow past it")
    func ceiling() {
        #expect(ChartLabSizing.mealSymbolSize(carbs: 100) == 400)
        #expect(ChartLabSizing.mealSymbolSize(carbs: 250) == 400)
    }
}

// MARK: - Meal response builder

@Suite("Meal response builder")
struct MealResponseBuilderTests {
    /// A clean 60 g meal: baseline 100 at −5, peak 154 at +50, back to 110 at
    /// +120. Paired 5 U meal bolus, nothing else logged.
    private func cleanFixture() -> (meals: [MealEntry], readings: [SensorGlucose], doses: [InsulinDelivery]) {
        var readings = [reading(-15, 98), reading(-10, 99), reading(-5, 100)]
        // 0 → 50 rising to 154, 50 → 120 falling back to 110.
        for step in 0 ... 10 {
            let minute = Double(step) * 5
            readings.append(reading(minute, 100 + Int((54.0 * Double(step) / 10.0).rounded())))
        }
        for step in 1 ... 13 {
            let minute = 50 + Double(step) * 5
            readings.append(reading(minute, 154 - Int((44.0 * Double(step) / 13.0).rounded())))
        }
        return ([meal(0, carbs: 60)], readings, [bolus(0, units: 5)])
    }

    @Test("a clean 60 g meal with +54 is not excluded")
    func cleanMealIsNotExcluded() {
        let fixture = cleanFixture()
        let built = buildMealResponses(
            meals: fixture.meals,
            readings: fixture.readings,
            deliveries: fixture.doses,
            exercise: [],
            domainStart: at(-720),
            domainEnd: at(240),
            now: at(300)
        )
        #expect(built.count == 1)
        #expect(built[0].exclusion == nil)
        #expect(built[0].summary.delta == 54)
        #expect(built[0].pairedBolusUnits == 5)
        #expect(built[0].confounders.isClean)
    }

    @Test("the ribbon clamps its right edge at the domain end")
    func clampsAtDomainEnd() {
        let fixture = cleanFixture()
        let built = buildMealResponses(
            meals: fixture.meals,
            readings: fixture.readings,
            deliveries: fixture.doses,
            exercise: [],
            domainStart: at(-720),
            domainEnd: at(30),
            now: at(300)
        )
        #expect(built.count == 1)
        #expect(built[0].windowEnd == at(30))
    }

    @Test("only an in-progress window carries a dotted stub")
    func stubOnlyWhileInProgress() {
        let fixture = cleanFixture()

        let live = buildMealResponses(
            meals: fixture.meals,
            readings: fixture.readings,
            deliveries: fixture.doses,
            exercise: [],
            domainStart: at(-720),
            domainEnd: at(240),
            now: at(38)
        )
        #expect(live[0].summary.isInProgress)
        #expect(live[0].windowEnd == at(38))
        #expect(live[0].stubEnd == at(120))

        let done = buildMealResponses(
            meals: fixture.meals,
            readings: fixture.readings,
            deliveries: fixture.doses,
            exercise: [],
            domainStart: at(-720),
            domainEnd: at(240),
            now: at(300)
        )
        #expect(done[0].stubEnd == nil)
    }

    @Test("no paired bolus excludes as NO BOLUS")
    func noBolusExclusion() {
        let fixture = cleanFixture()
        let built = buildMealResponses(
            meals: fixture.meals,
            readings: fixture.readings,
            deliveries: [],
            exercise: [],
            domainStart: at(-720),
            domainEnd: at(240),
            now: at(300)
        )
        #expect(built[0].exclusion == .noBolus)
        #expect(built[0].ribbonLabel(glucoseUnit: .mgdL) == "NO BOLUS")
    }

    @Test("10 g with a bolus excludes as SMALL MEAL")
    func smallMealExclusion() {
        let fixture = cleanFixture()
        let built = buildMealResponses(
            meals: [meal(0, carbs: 10)],
            readings: fixture.readings,
            deliveries: [bolus(0, units: 1)],
            exercise: [],
            domainStart: at(-720),
            domainEnd: at(240),
            now: at(300)
        )
        #expect(built[0].exclusion == .smallMeal)
        #expect(built[0].ribbonLabel(glucoseUnit: .mgdL) == "SMALL MEAL")
    }

    @Test("a correction bolus in the window excludes as confounded, tagged CORR")
    func correctionConfounder() {
        let fixture = cleanFixture()
        let built = buildMealResponses(
            meals: fixture.meals,
            readings: fixture.readings,
            deliveries: fixture.doses + [bolus(45, units: 2, type: .correctionBolus)],
            exercise: [],
            domainStart: at(-720),
            domainEnd: at(240),
            now: at(300)
        )
        #expect(built[0].exclusion == .confounded)
        #expect(built[0].confounders.hasCorrectionBolus)
        #expect(built[0].ribbonLabel(glucoseUnit: .mgdL) == "CORR")
    }

    @Test("overlapping exercise excludes as confounded, tagged EXERCISE")
    func exerciseConfounder() {
        let fixture = cleanFixture()
        let built = buildMealResponses(
            meals: fixture.meals,
            readings: fixture.readings,
            deliveries: fixture.doses,
            exercise: [workout(from: 30, to: 60)],
            domainStart: at(-720),
            domainEnd: at(240),
            now: at(300)
        )
        #expect(built[0].exclusion == .confounded)
        #expect(built[0].ribbonLabel(glucoseUnit: .mgdL) == "EXERCISE")
    }

    @Test("a hypo inside the window excludes as HYPO, ahead of the return-to-baseline check")
    func hypoExclusion() {
        var readings = [reading(-5, 100)]
        for step in 0 ... 24 {
            let minute = Double(step) * 5
            readings.append(reading(minute, step >= 12 ? 62 : 120))
        }
        let built = buildMealResponses(
            meals: [meal(0, carbs: 60)],
            readings: readings,
            deliveries: [bolus(0, units: 5)],
            exercise: [],
            domainStart: at(-720),
            domainEnd: at(240),
            now: at(300)
        )
        #expect(built[0].exclusion == .hypoInWindow)
        #expect(built[0].ribbonLabel(glucoseUnit: .mgdL) == "HYPO")
    }

    @Test("a completed window that ends 54 above baseline excludes as ENDED +54")
    func didNotReturnExclusion() {
        var readings = [reading(-5, 100)]
        for step in 0 ... 24 {
            let minute = Double(step) * 5
            readings.append(reading(minute, 100 + Int((54.0 * min(Double(step), 12.0) / 12.0).rounded())))
        }
        let built = buildMealResponses(
            meals: [meal(0, carbs: 60)],
            readings: readings,
            deliveries: [bolus(0, units: 5)],
            exercise: [],
            domainStart: at(-720),
            domainEnd: at(240),
            now: at(300)
        )
        #expect(built[0].exclusion == .didNotReturnToBaseline(deltaMgDL: 54))
        #expect(built[0].ribbonLabel(glucoseUnit: .mgdL) == "ENDED +54")
    }

    @Test("an in-progress window is never judged on where it ended")
    func inProgressIsNotJudgedOnEnd() {
        var readings = [reading(-5, 100)]
        for step in 0 ... 7 {
            readings.append(reading(Double(step) * 5, 100 + step * 8))
        }
        let built = buildMealResponses(
            meals: [meal(0, carbs: 60)],
            readings: readings,
            deliveries: [bolus(0, units: 5)],
            exercise: [],
            domainStart: at(-720),
            domainEnd: at(240),
            now: at(38)
        )
        #expect(built[0].exclusion == nil)
        #expect(built[0].summary.isInProgress)
    }

    @Test("meals outside the domain (plus the 2 h tail) are not built")
    func outsideDomainIsSkipped() {
        let fixture = cleanFixture()
        let built = buildMealResponses(
            meals: [meal(-600, carbs: 60), meal(0, carbs: 60), meal(400, carbs: 60)],
            readings: fixture.readings,
            deliveries: fixture.doses,
            exercise: [],
            domainStart: at(-200),
            domainEnd: at(240),
            now: at(600)
        )
        #expect(built.count == 1)
        #expect(built[0].mealTime == at(0))
    }

    @Test("a live ribbon reads elapsed minutes; a closed one reads its peak — both with n")
    func ribbonLabelShapes() {
        let fixture = cleanFixture()

        let live = buildMealResponses(
            meals: fixture.meals,
            readings: fixture.readings,
            deliveries: fixture.doses,
            exercise: [],
            domainStart: at(-720),
            domainEnd: at(240),
            now: at(38)
        )[0]
        #expect(live.ribbonLabel(glucoseUnit: .mgdL).hasSuffix("RDG"))
        #expect(live.ribbonLabel(glucoseUnit: .mgdL).contains("38 MIN"))

        let done = buildMealResponses(
            meals: fixture.meals,
            readings: fixture.readings,
            deliveries: fixture.doses,
            exercise: [],
            domainStart: at(-720),
            domainEnd: at(240),
            now: at(300)
        )[0]
        #expect(done.ribbonLabel(glucoseUnit: .mgdL) == "+54 · PEAK 50m · 24 RDG")
    }

    @Test("the bracket is a pairing, never a ratio — and it converts nothing")
    func bracketLabel() {
        let fixture = cleanFixture()
        let built = buildMealResponses(
            meals: fixture.meals,
            readings: fixture.readings,
            deliveries: fixture.doses,
            exercise: [],
            domainStart: at(-720),
            domainEnd: at(240),
            now: at(300)
        )[0]
        #expect(built.bracketLabel == "60g ⟷ 5U")

        let unpaired = buildMealResponses(
            meals: [meal(0, carbs: 10)],
            readings: fixture.readings,
            deliveries: [],
            exercise: [],
            domainStart: at(-720),
            domainEnd: at(240),
            now: at(300)
        )[0]
        #expect(unpaired.bracketLabel == "10g")
    }

    @Test("mmol/L converts the label's glucose, not its grams or units")
    func mmolLabels() {
        let fixture = cleanFixture()
        let built = buildMealResponses(
            meals: fixture.meals,
            readings: fixture.readings,
            deliveries: fixture.doses,
            exercise: [],
            domainStart: at(-720),
            domainEnd: at(240),
            now: at(300)
        )[0]
        let label = built.ribbonLabel(glucoseUnit: .mmolL)
        #expect(label.contains("PEAK 50m"))
        #expect(label.contains("24 RDG"))
        #expect(label.contains("54") == false, "a mg/dL delta must not leak into an mmol/L label")
        #expect(built.bracketLabel == "60g ⟷ 5U")
    }
}

// MARK: - Residual detector

@Suite("Residual detector")
struct ResidualDetectorTests {
    /// Flat 100 for two hours, a +45 ramp over an hour, then flat.
    private func rampFixture(rampStart: Double = 0) -> [SensorGlucose] {
        var readings: [SensorGlucose] = []
        var minute = rampStart - 120
        while minute < rampStart {
            readings.append(reading(minute, 100))
            minute += 5
        }
        for step in 0 ... 12 {
            readings.append(reading(rampStart + Double(step) * 5, 100 + Int((45.0 * Double(step) / 12.0).rounded())))
        }
        minute = rampStart + 65
        while minute <= rampStart + 180 {
            readings.append(reading(minute, 145))
            minute += 5
        }
        return readings
    }

    @Test("a +45 rise with nothing logged is one residual, carrying its n")
    func unexplainedRise() {
        let segments = ResidualDetector.detect(readings: rampFixture(), anchors: [], regimes: [])
        #expect(segments.count == 1)
        #expect(segments[0].deltaMgDL >= 40)
        #expect(segments[0].n >= 4)
        #expect(segments[0].start < segments[0].end)
    }

    @Test("a meal 20 minutes before the rise explains it away")
    func anchoredRiseIsNotResidual() {
        let segments = ResidualDetector.detect(
            readings: rampFixture(),
            anchors: [at(-20)],
            regimes: []
        )
        #expect(segments.isEmpty)
    }

    @Test("a compression-style 30 mg/dL step inside the candidate is rejected as noise")
    func noiseGuard() {
        var readings: [SensorGlucose] = []
        for step in 0 ... 3 { readings.append(reading(Double(step) * 5, 100)) }
        readings.append(reading(20, 130))   // the 30-point jump
        readings.append(reading(25, 135))
        readings.append(reading(30, 140))
        readings.append(reading(35, 145))
        for step in 8 ... 20 { readings.append(reading(Double(step) * 5, 145)) }

        #expect(ResidualDetector.detect(readings: readings, anchors: [], regimes: []).isEmpty)
    }

    @Test("overlapping candidates merge into one segment; distant ones stay apart")
    func mergesOverlapping() {
        let first = rampFixture(rampStart: 0)
        var second: [SensorGlucose] = []
        for step in 0 ... 12 {
            second.append(reading(600 + Double(step) * 5, 145 - Int((45.0 * Double(step) / 12.0).rounded())))
        }
        var tail: [SensorGlucose] = []
        var minute = 665.0
        while minute <= 800 {
            tail.append(reading(minute, 100))
            minute += 5
        }

        let segments = ResidualDetector.detect(
            readings: first + second + tail,
            anchors: [],
            regimes: []
        )
        #expect(segments.count == 2)
        #expect(segments[0].end < segments[1].start)
    }

    @Test("a regime band covering the excursion is an explanation, so no residual")
    func regimeSuppresses() {
        let band = RegimeBand(
            id: "fixture",
            tag: .stressed,
            start: at(-90),
            end: at(90),
            isOpen: false
        )
        #expect(ResidualDetector.detect(readings: rampFixture(), anchors: [], regimes: [band]).isEmpty)
    }

    @Test("too few readings is not a residual, however big the swing")
    func tooFewReadings() {
        let readings = [reading(0, 100), reading(30, 150), reading(60, 155)]
        #expect(ResidualDetector.detect(readings: readings, anchors: [], regimes: []).isEmpty)
    }
}

// MARK: - Regime deriver

@Suite("Regime deriver")
struct RegimeDeriverTests {
    private let dayEnd = at(600)

    @Test("STRESSED opens a four-hour band")
    func stressedIsFourHours() {
        let bands = RegimeDeriver.derive(notes: [note(0, tag: .stressed)], now: at(60), dayEnd: dayEnd)
        #expect(bands.count == 1)
        #expect(bands[0].start == at(0))
        #expect(bands[0].end == at(240))
        #expect(bands[0].isOpen)
    }

    @Test("SICK with no later note runs 24 h and stays open")
    func sickRunsADay() {
        let bands = RegimeDeriver.derive(notes: [note(0, tag: .sick)], now: at(60), dayEnd: dayEnd)
        #expect(bands.count == 1)
        #expect(bands[0].end == at(24 * 60))
        #expect(bands[0].isOpen)
    }

    @Test("SLUGGISH runs to the end of the day")
    func sluggishRunsToDayEnd() {
        let bands = RegimeDeriver.derive(notes: [note(0, tag: .sluggish)], now: at(60), dayEnd: dayEnd)
        #expect(bands[0].end == dayEnd)
    }

    @Test("OTHER is a note, not a regime")
    func otherYieldsNoBand() {
        #expect(RegimeDeriver.derive(notes: [note(0, tag: .other)], now: at(60), dayEnd: dayEnd).isEmpty)
    }

    @Test("an untagged note is a note, not a regime")
    func untaggedYieldsNoBand() {
        #expect(RegimeDeriver.derive(notes: [note(0, tag: nil)], now: at(60), dayEnd: dayEnd).isEmpty)
    }

    @Test("a later tagged note closes the earlier band early")
    func laterTaggedNoteCloses() {
        let bands = RegimeDeriver.derive(
            notes: [note(0, tag: .stressed), note(90, tag: .sick)],
            now: at(120),
            dayEnd: dayEnd
        )
        #expect(bands.count == 2)
        #expect(bands[0].end == at(90))
        #expect(bands[0].isOpen == false)
        #expect(bands[1].start == at(90))
        #expect(bands[1].isOpen)
    }

    @Test("BACK TO NORMAL closes the band without opening one")
    func backToNormalCloses() {
        let bands = RegimeDeriver.derive(
            notes: [note(0, tag: .stressed), note(75, tag: nil, text: "BACK TO NORMAL")],
            now: at(120),
            dayEnd: dayEnd
        )
        #expect(bands.count == 1)
        #expect(bands[0].end == at(75))
        #expect(bands[0].isOpen == false)
    }

    @Test("a close marker AFTER the default end still closes the band, without extending it")
    func closerAfterDefaultEndStillCloses() {
        // The exact shape the `STILL <TAG>?` row produces: the row is shown at
        // the default end, so the answer necessarily lands after it.
        let bands = RegimeDeriver.derive(
            notes: [note(0, tag: .stressed), note(283, tag: nil, text: "BACK TO NORMAL")],
            now: at(283),
            dayEnd: dayEnd
        )
        #expect(bands.count == 1)
        #expect(bands[0].end == at(240), "a late answer must not extend the band past its default")
        #expect(bands[0].isOpen == false)
        #expect(RegimePrompt.shouldShow(bands: bands, now: at(283)) == nil, "and the row must go away")
    }

    @Test("notes arrive in any order and still derive in time order")
    func unsortedNotes() {
        let bands = RegimeDeriver.derive(
            notes: [note(90, tag: .sick), note(0, tag: .stressed)],
            now: at(120),
            dayEnd: dayEnd
        )
        #expect(bands.count == 2)
        #expect(bands[0].tag == .stressed)
        #expect(bands[1].tag == .sick)
    }

    @Test("the band's label names its tag and its hours, never a prescription")
    func bandLabel() {
        let bands = RegimeDeriver.derive(notes: [note(0, tag: .stressed)], now: at(60), dayEnd: dayEnd)
        let label = bands[0].label
        #expect(label.hasPrefix("STRESSED "))
        #expect(label.contains("→"))
    }
}

// MARK: - Regime prompt

@Suite("Regime prompt")
struct RegimePromptTests {
    private func stressedBand(open: Bool = true) -> RegimeBand {
        RegimeBand(id: "b", tag: .stressed, start: at(0), end: at(240), isOpen: open)
    }

    @Test("nothing is asked before the band's last half hour")
    func quietEarly() {
        #expect(RegimePrompt.shouldShow(bands: [stressedBand()], now: at(120)) == nil)
    }

    @Test("the prompt appears 30 minutes before the default end")
    func showsNearTheEnd() {
        #expect(RegimePrompt.shouldShow(bands: [stressedBand()], now: at(210))?.tag == .stressed)
        #expect(RegimePrompt.shouldShow(bands: [stressedBand()], now: at(260))?.tag == .stressed)
    }

    @Test("a band the user already closed is never asked about")
    func closedBandIsNotAsked() {
        #expect(RegimePrompt.shouldShow(bands: [stressedBand(open: false)], now: at(260)) == nil)
    }

    @Test("with several open bands the most recent one is asked about")
    func mostRecentWins() {
        let older = RegimeBand(id: "a", tag: .sick, start: at(-600), end: at(840), isOpen: true)
        let newer = stressedBand()
        #expect(RegimePrompt.shouldShow(bands: [older, newer], now: at(260))?.tag == .stressed)
    }
}

// MARK: - Ribbon label stagger

@Suite("Ribbon label lanes")
struct RibbonLabelLaneTests {
    private func response(_ minutes: Double, carbs: Double = 40) -> MealResponseDatapoint {
        buildMealResponses(
            meals: [meal(minutes, carbs: carbs)],
            readings: [reading(minutes, 120)],
            deliveries: [bolus(minutes, units: 4)],
            exercise: [],
            domainStart: at(-720),
            domainEnd: at(720),
            now: at(1200)
        )[0]
    }

    @Test("consecutive meals never share a row — the LABEL collides, not the window")
    func consecutiveMealsStepDown() {
        // Four hours apart: the windows do not overlap at all, but at 24 h zoom
        // a ~110 pt label over a ~30 pt ribbon still prints over its neighbour.
        let first = response(0)
        let second = response(240)
        let third = response(480)
        let lanes = MealResponseDatapoint.labelLanes([first, second, third])
        #expect(lanes[first.id] == 0)
        #expect(lanes[second.id] == 1)
        #expect(lanes[third.id] == 2)
    }

    @Test("rows are assigned in TIME order, whatever order the meals arrive in")
    func assignedInTimeOrder() {
        let later = response(240)
        let earlier = response(0)
        let lanes = MealResponseDatapoint.labelLanes([later, earlier])
        #expect(lanes[earlier.id] == 0)
        #expect(lanes[later.id] == 1)
    }

    @Test("the rows cycle, so the budget is never exceeded")
    func staysInsideTheRowBudget() {
        let responses = (0 ..< 6).map { response(Double($0) * 10) }
        let lanes = MealResponseDatapoint.labelLanes(responses)
        #expect(lanes.count == 6)
        #expect(lanes.values.allSatisfy { $0 >= 0 && $0 < 4 })
        #expect(lanes[responses[4].id] == 0, "the fifth meal wraps back to the first row")
    }
}
