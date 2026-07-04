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

func computeMealOverlayDelta(
    meal: MealEntry,
    isInProgress: Bool,
    sensorGlucoseValues: [SensorGlucose]
) -> MealOverlayDelta {
    let windowEnd = isInProgress ? Date() : meal.timestamp.addingTimeInterval(2 * 60 * 60)

    let readings = sensorGlucoseValues.filter { glucose in
        glucose.timestamp >= meal.timestamp && glucose.timestamp <= windowEnd
    }

    guard !readings.isEmpty else {
        return MealOverlayDelta(delta: nil, isLowConfidence: false)
    }

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
        return MealOverlayDelta(delta: nil, isLowConfidence: false)
    }

    guard let peak = readings.max(by: { $0.glucoseValue < $1.glucoseValue }) else {
        return MealOverlayDelta(delta: nil, isLowConfidence: false)
    }
    let delta = peak.glucoseValue - referenceGlucose
    let isLowConfidence = readings.count < 4

    return MealOverlayDelta(delta: delta, isLowConfidence: isLowConfidence)
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
