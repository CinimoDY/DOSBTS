//
//  MealOverlayLogic.swift
//  DOSBTS
//
//  Free-function helpers extracted from ChartView so EntryGroupListOverlay
//  (and other consumers) can call them without a store dependency.
//

import Foundation
import SwiftUI

// MARK: - Delta Tier Color

/// Color-code a glucose delta using the MealImpact tier bands.
/// < 30 mg/dL → green (minimal spike)
/// 30–59 mg/dL → amber (moderate spike)
/// ≥ 60 mg/dL → red (significant spike)
func mealImpactDeltaColor(delta: Int) -> Color {
    if delta >= 60 { return AmberTheme.cgaRed }
    if delta >= 30 { return AmberTheme.amber }
    return AmberTheme.cgaGreen
}

// MARK: - Delta

struct MealOverlayDelta {
    let delta: Int?
    let isLowConfidence: Bool
}

/// A thin wrapper over `ResponseKernel` since DMNC-1501 — the arithmetic it used
/// to carry inline now lives in `Library/Content/ResponseWindow.swift` so the
/// Chart Lab's meal ribbons, and later exercise and sleep, all read the same
/// cause→effect window. The numbers are unchanged: `MealOverlayDeltaParityTests`
/// runs the pre-refactor algorithm as an oracle against this function.
func computeMealOverlayDelta(
    meal: MealEntry,
    isInProgress: Bool,
    sensorGlucoseValues: [SensorGlucose]
) -> MealOverlayDelta {
    // The old `windowEnd`, expressed as the kernel's `now`: the kernel closes
    // the window at `min(anchor + 2 h, now)`, which for an honestly-computed
    // `isInProgress` is exactly the same instant.
    let now = isInProgress ? Date() : meal.timestamp.addingTimeInterval(ResponseKernel.mealLagSeconds)

    let summary = ResponseKernel.summarize(
        .meal(at: meal.timestamp),
        readings: sensorGlucoseValues,
        now: now
    )

    return MealOverlayDelta(delta: summary.delta, isLowConfidence: summary.isLowConfidence)
}

// MARK: - Confounders

struct MealConfounders {
    let hasCorrectionBolus: Bool
    let hasExercise: Bool
    let hasStackedMeal: Bool
    var isClean: Bool { !hasCorrectionBolus && !hasExercise && !hasStackedMeal }
}

func detectMealConfounders(
    meal: MealEntry,
    insulinDeliveryValues: [InsulinDelivery],
    exerciseEntryValues: [ExerciseEntry],
    mealEntryValues: [MealEntry]
) -> MealConfounders {
    let windowEnd = meal.timestamp.addingTimeInterval(2 * 60 * 60)

    let hasCorrectionBolus = insulinDeliveryValues.contains { delivery in
        delivery.starts >= meal.timestamp && delivery.starts <= windowEnd && delivery.type == .correctionBolus
    }

    let hasExercise = exerciseEntryValues.contains { exercise in
        exercise.startTime <= windowEnd && exercise.endTime >= meal.timestamp
    }

    let hasStackedMeal = mealEntryValues.contains { other in
        other.id != meal.id && other.timestamp >= meal.timestamp && other.timestamp <= windowEnd
    }

    return MealConfounders(
        hasCorrectionBolus: hasCorrectionBolus,
        hasExercise: hasExercise,
        hasStackedMeal: hasStackedMeal
    )
}
