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
