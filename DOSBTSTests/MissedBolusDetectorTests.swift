//
//  MissedBolusDetectorTests.swift
//  DOSBTSTests
//
//  Pure detector matrix for MissedBolusDetector (DMNC-1300, WP-N1).
//  See docs/plans/2026-07-03-mdi-companion-features-plan.md § WP-N1.
//

import Foundation
import Testing
@testable import DOSBTSApp

// MARK: - Fixtures

// Base meal time on a minute boundary so .toRounded() doesn't shift it.
private let baseMealTime = Date(timeIntervalSince1970: 0) // 1970-01-01T00:00:00Z — on minute boundary

private func makeMeal(
    carbs: Double?,
    at timestamp: Date = baseMealTime,
    description: String = "test meal"
) -> MealEntry {
    MealEntry(timestamp: timestamp, mealDescription: description, carbsGrams: carbs)
}

private func makeBolus(type: InsulinType = .mealBolus, units: Double = 5, offsetSeconds: Double) -> InsulinDelivery {
    let starts = baseMealTime.addingTimeInterval(offsetSeconds)
    return InsulinDelivery(starts: starts, ends: starts, units: units, type: type)
}

private func shouldNudge(
    meal: MealEntry,
    deliveries: [InsulinDelivery] = [],
    // Production evaluates at grace expiry (~20 min after the meal), so paired
    // boluses logged minutes after eating are in the past by evaluation time.
    now: Date = baseMealTime.addingTimeInterval(20 * 60),
    treatmentCycleActive: Bool = false,
    isHypoTreatmentMeal: Bool = false,
    showMissedBolusNudge: Bool = true,
    nudgedMealIds: Set<UUID> = []
) -> Bool {
    MissedBolusDetector.shouldNudge(
        meal: meal,
        deliveries: deliveries,
        now: now,
        treatmentCycleActive: treatmentCycleActive,
        isHypoTreatmentMeal: isHypoTreatmentMeal,
        showMissedBolusNudge: showMissedBolusNudge,
        nudgedMealIds: nudgedMealIds
    )
}

// MARK: - MissedBolusDetectorTests

@Suite("MissedBolusDetector")
struct MissedBolusDetectorTests {

    // MARK: Carbs threshold

    @Test("carbs below threshold: no nudge")
    func carbsBelowThreshold() {
        let meal = makeMeal(carbs: 10)
        #expect(shouldNudge(meal: meal) == false)
    }

    @Test("carbs exactly at threshold: nudge")
    func carbsAtThreshold() {
        let meal = makeMeal(carbs: 15)
        #expect(shouldNudge(meal: meal) == true)
    }

    @Test("nil carbs treated as zero: no nudge")
    func nilCarbs() {
        let meal = makeMeal(carbs: nil)
        #expect(shouldNudge(meal: meal) == false)
    }

    // MARK: Pairing window

    @Test("bolus at +12 min (within window): no nudge")
    func bolusWithinWindow() {
        let meal = makeMeal(carbs: 30)
        let bolus = makeBolus(offsetSeconds: 12 * 60)
        #expect(shouldNudge(meal: meal, deliveries: [bolus]) == false)
    }

    @Test("bolus at +20 min (outside window): nudge fires")
    func bolusOutsideWindow() {
        let meal = makeMeal(carbs: 30)
        let bolus = makeBolus(offsetSeconds: 20 * 60)
        #expect(shouldNudge(meal: meal, deliveries: [bolus]) == true)
    }

    @Test("correction bolus within window does not count: nudge fires")
    func correctionBolusIgnored() {
        let meal = makeMeal(carbs: 30)
        let correction = makeBolus(type: .correctionBolus, offsetSeconds: 5 * 60)
        #expect(shouldNudge(meal: meal, deliveries: [correction]) == true)
    }

    @Test("snack bolus within window counts: no nudge")
    func snackBolusCountsAsPaired() {
        let meal = makeMeal(carbs: 30)
        let snack = makeBolus(type: .snackBolus, offsetSeconds: 5 * 60)
        #expect(shouldNudge(meal: meal, deliveries: [snack]) == false)
    }

    @Test("multiple boluses summing below 0.5 U: nudge fires")
    func tinyBolusSumBelowMinimum() {
        let meal = makeMeal(carbs: 30)
        let tiny1 = makeBolus(units: 0.2, offsetSeconds: 5 * 60)
        let tiny2 = makeBolus(units: 0.2, offsetSeconds: 8 * 60)
        #expect(shouldNudge(meal: meal, deliveries: [tiny1, tiny2]) == true)
    }

    @Test("multiple boluses summing above 0.5 U: no nudge")
    func bolussumAboveMinimum() {
        let meal = makeMeal(carbs: 30)
        let b1 = makeBolus(units: 0.3, offsetSeconds: 5 * 60)
        let b2 = makeBolus(units: 0.3, offsetSeconds: 8 * 60)
        #expect(shouldNudge(meal: meal, deliveries: [b1, b2]) == false)
    }

    // MARK: Suppression

    @Test("treatment cycle active: no nudge")
    func treatmentCycleActive() {
        let meal = makeMeal(carbs: 30)
        #expect(shouldNudge(meal: meal, treatmentCycleActive: true) == false)
    }

    @Test("hypo-treatment favorite: no nudge")
    func hypoTreatmentMeal() {
        let meal = makeMeal(carbs: 30)
        #expect(shouldNudge(meal: meal, isHypoTreatmentMeal: true) == false)
    }

    @Test("toggle off: no nudge")
    func toggleOff() {
        let meal = makeMeal(carbs: 30)
        #expect(shouldNudge(meal: meal, showMissedBolusNudge: false) == false)
    }

    // MARK: Dedup

    @Test("second evaluation of same meal: no nudge")
    func dedup() {
        let meal = makeMeal(carbs: 30)
        #expect(shouldNudge(meal: meal, nudgedMealIds: [meal.id]) == false)
    }

    // MARK: Future-dated deliveries

    @Test("future-dated bolus does not count as coverage")
    func futureDatedBolusExcluded() {
        let meal = makeMeal(carbs: 30)
        let bolus = makeBolus(offsetSeconds: 5 * 60)
        // Evaluate BEFORE the bolus's start time: it hasn't been delivered yet,
        // so the meal counts as uncovered (mirrors the IOB convention).
        #expect(shouldNudge(meal: meal, deliveries: [bolus], now: baseMealTime) == true)
        // At grace expiry the same bolus is in the past and covers the meal.
        #expect(shouldNudge(meal: meal, deliveries: [bolus]) == false)
    }
}

// MARK: - Reducer Helper

private func reduce(_ state: inout DirectState, _ action: DirectAction) {
    directReducer(state: &state, action: action)
}

// MARK: - MissedBolusNudgeReducerTests

@Suite("Missed-Bolus Nudge Reducer")
struct MissedBolusNudgeReducerTests {

    @Test("setShowMissedBolusNudge toggles the setting")
    func toggleSetting() {
        var state: DirectState = AppState(defaults: makeTestDefaults())
        #expect(state.showMissedBolusNudge == true)

        reduce(&state, .setShowMissedBolusNudge(enabled: false))
        #expect(state.showMissedBolusNudge == false)

        reduce(&state, .setShowMissedBolusNudge(enabled: true))
        #expect(state.showMissedBolusNudge == true)
    }

    @Test("showMissedBolusNudge persists to UserDefaults")
    func persistsToUserDefaults() {
        let defaults = makeTestDefaults()
        var writer: DirectState = AppState(defaults: defaults)
        #expect(writer.showMissedBolusNudge == true)

        reduce(&writer, .setShowMissedBolusNudge(enabled: false))

        let reloaded = AppState(defaults: defaults)
        #expect(reloaded.showMissedBolusNudge == false)
    }
}
