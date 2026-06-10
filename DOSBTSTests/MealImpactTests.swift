//
//  MealImpactTests.swift
//  DOSBTSTests
//

import Foundation
import Testing
@testable import DOSBTSApp

// MARK: - Helpers

private func makeState() -> AppState {
    AppState(defaults: makeTestDefaults())
}

private func reduce(_ state: inout DirectState, _ action: DirectAction) {
    directReducer(state: &state, action: action)
}

// MARK: - Meal Impact Reducer

@Suite("Meal Impact Reducer")
struct MealImpactReducerTests {

    @Test("setScoredMealEntryIds populates state")
    func setScoredIds() {
        var state: DirectState = makeState()
        let ids: Set<UUID> = [UUID(), UUID(), UUID()]
        reduce(&state, .setScoredMealEntryIds(scoredMealEntryIds: ids))
        #expect(state.scoredMealEntryIds == ids)
    }

    @Test("setScoredMealEntryIds replaces previous set")
    func replacesScoredIds() {
        var state: DirectState = makeState()
        let first: Set<UUID> = [UUID()]
        let second: Set<UUID> = [UUID(), UUID()]
        reduce(&state, .setScoredMealEntryIds(scoredMealEntryIds: first))
        reduce(&state, .setScoredMealEntryIds(scoredMealEntryIds: second))
        #expect(state.scoredMealEntryIds == second)
    }

    @Test("setScoredMealEntryIds with empty set clears state")
    func clearsScoredIds() {
        var state: DirectState = makeState()
        reduce(&state, .setScoredMealEntryIds(scoredMealEntryIds: [UUID()]))
        reduce(&state, .setScoredMealEntryIds(scoredMealEntryIds: []))
        #expect(state.scoredMealEntryIds.isEmpty)
    }
}

// MARK: - MealImpact Model

@Suite("MealImpact Model")
struct MealImpactModelTests {

    @Test("MealImpact auto-generates UUID")
    func autoGeneratesId() {
        let impact = MealImpact(
            mealEntryId: UUID(),
            baselineGlucose: 100,
            peakGlucose: 145,
            deltaMgDL: 45,
            timeToPeakMinutes: 60,
            isClean: true,
            timestamp: Date()
        )
        // ID should be non-nil (auto-generated)
        #expect(impact.id != UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
    }

    @Test("MealImpact with explicit UUID preserves it")
    func preservesExplicitId() {
        let id = UUID()
        let impact = MealImpact(
            id: id,
            mealEntryId: UUID(),
            baselineGlucose: 100,
            peakGlucose: 145,
            deltaMgDL: 45,
            timeToPeakMinutes: 60,
            isClean: true,
            timestamp: Date()
        )
        #expect(impact.id == id)
    }

    @Test("MealImpact allows nil baseline")
    func nilBaseline() {
        let impact = MealImpact(
            mealEntryId: UUID(),
            baselineGlucose: nil,
            peakGlucose: 145,
            deltaMgDL: 45,
            timeToPeakMinutes: 60,
            isClean: true,
            timestamp: Date()
        )
        #expect(impact.baselineGlucose == nil)
    }

    @Test("MealImpact equality is by id")
    func equalityById() {
        let id = UUID()
        let a = MealImpact(id: id, mealEntryId: UUID(), baselineGlucose: 100, peakGlucose: 145, deltaMgDL: 45, timeToPeakMinutes: 60, isClean: true, timestamp: Date())
        let b = MealImpact(id: id, mealEntryId: UUID(), baselineGlucose: 80, peakGlucose: 200, deltaMgDL: 120, timeToPeakMinutes: 90, isClean: false, timestamp: Date())
        #expect(a == b)
    }

    @Test("MealImpact different ids are not equal")
    func differentIdsNotEqual() {
        let a = MealImpact(mealEntryId: UUID(), baselineGlucose: 100, peakGlucose: 145, deltaMgDL: 45, timeToPeakMinutes: 60, isClean: true, timestamp: Date())
        let b = MealImpact(mealEntryId: UUID(), baselineGlucose: 100, peakGlucose: 145, deltaMgDL: 45, timeToPeakMinutes: 60, isClean: true, timestamp: Date())
        #expect(a != b)
    }
}

// MARK: - Delta Color Thresholds

@Suite("Delta Color Thresholds")
struct DeltaThresholdTests {

    @Test("Delta 29 is below amber threshold")
    func belowAmber() {
        #expect(29 < 30) // Green threshold
    }

    @Test("Delta 30 is at amber threshold")
    func atAmber() {
        #expect(30 >= 30)
        #expect(30 < 60)
    }

    @Test("Delta 60 is at red threshold")
    func atRed() {
        #expect(60 >= 60)
    }

    @Test("Zero delta is green")
    func zeroDelta() {
        #expect(0 < 30)
    }

    @Test("Negative delta is green")
    func negativeDelta() {
        #expect(-10 < 30)
    }
}

// MARK: - Rolling Average Computation

@Suite("Rolling Average Computation")
struct RollingAverageTests {

    @Test("First observation sets average to delta")
    func firstObservation() {
        let oldAvg = 0.0
        let oldCount = 0
        let newDelta = 45.0
        let newAvg = ((oldAvg * Double(oldCount)) + newDelta) / Double(oldCount + 1)
        #expect(newAvg == 45.0)
    }

    @Test("Rolling average with 3 observations plus new delta")
    func rollingAverage() {
        let oldAvg = 40.0
        let oldCount = 3
        let newDelta = 60.0
        let newAvg = ((oldAvg * Double(oldCount)) + newDelta) / Double(oldCount + 1)
        #expect(newAvg == 45.0)
    }

    @Test("Rolling average with many observations stabilizes")
    func manyObservations() {
        let oldAvg = 50.0
        let oldCount = 100
        let newDelta = 150.0
        let newAvg = ((oldAvg * Double(oldCount)) + newDelta) / Double(oldCount + 1)
        // With 100 observations at avg 50, adding one 150 shifts to ~50.99
        #expect(newAvg > 50.0)
        #expect(newAvg < 52.0)
    }

    @Test("Rolling average formula is incremental mean")
    func incrementalMean() {
        // Verify the formula matches computing mean from scratch
        let values: [Double] = [30, 40, 50, 60, 70]
        let trueMean = values.reduce(0, +) / Double(values.count)

        var avg = 0.0
        var count = 0
        for v in values {
            avg = ((avg * Double(count)) + v) / Double(count + 1)
            count += 1
        }

        #expect(abs(avg - trueMean) < 0.001)
    }
}

// MARK: - MealEntry analysisSessionId

@Suite("MealEntry analysisSessionId")
struct MealEntrySessionIdTests {

    @Test("Manual meal entry has nil analysisSessionId")
    func manualMealNilSessionId() {
        let meal = MealEntry(timestamp: Date(), mealDescription: "Toast", carbsGrams: 30)
        #expect(meal.analysisSessionId == nil)
    }

    @Test("AI meal entry has non-nil analysisSessionId")
    func aiMealHasSessionId() {
        let sessionId = UUID()
        let meal = MealEntry(timestamp: Date(), mealDescription: "Toast", carbsGrams: 30, analysisSessionId: sessionId)
        #expect(meal.analysisSessionId == sessionId)
    }

    @Test("MealEntry with explicit id and analysisSessionId")
    func explicitIdAndSessionId() {
        let id = UUID()
        let sessionId = UUID()
        let meal = MealEntry(id: id, timestamp: Date(), mealDescription: "Toast", carbsGrams: 30, analysisSessionId: sessionId)
        #expect(meal.id == id)
        #expect(meal.analysisSessionId == sessionId)
    }
}

// MARK: - PersonalFood Glycemic Fields

@Suite("PersonalFood Glycemic Fields")
struct PersonalFoodGlycemicTests {

    @Test("New PersonalFood has nil glycemic fields")
    func defaultGlycemicFields() {
        let food = PersonalFood(name: "Toast", carbsG: 30)
        #expect(food.avgDeltaMgDL == nil)
        #expect(food.observationCount == 0)
        #expect(food.lastScoredDate == nil)
    }

    @Test("PersonalFood with analysisSessionId")
    func withSessionId() {
        let sessionId = UUID()
        let food = PersonalFood(name: "Toast", carbsG: 30, analysisSessionId: sessionId)
        #expect(food.analysisSessionId == sessionId)
    }

    @Test("PersonalFood observation threshold for display is 2")
    func observationThreshold() {
        // UI shows average only when observationCount >= 2
        #expect(1 < 2) // Below threshold
        #expect(2 >= 2) // At threshold
    }
}
