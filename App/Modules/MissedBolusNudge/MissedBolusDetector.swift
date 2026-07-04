//
//  MissedBolusDetector.swift
//  DOSBTS
//

import Foundation

// MARK: - MissedBolusDetector

/// Pure logic for deciding whether to schedule a missed-bolus nudge.
/// Extracted so the decision can be unit-tested independently of UNUserNotificationCenter.
enum MissedBolusDetector {
    static let carbsThresholdGrams: Double = 15
    /// ±15 min pairing window — identical to Ratio Lab's definition.
    static let pairingWindowSeconds: Double = 15 * 60
    /// Minimum summed bolus (mealBolus + snackBolus) that counts as "bolused" — identical to Ratio Lab.
    static let minPairedBolusUnits: Double = 0.5

    /// Returns true when a missed-bolus nudge should be scheduled for `meal`.
    ///
    /// - Parameters:
    ///   - meal: The newly-logged meal entry.
    ///   - deliveries: All insulin deliveries currently in state (post-reducer).
    ///   - now: Wall-clock time at evaluation (injectable for testing).
    ///   - treatmentCycleActive: Suppress during hypo treatment cycles.
    ///   - isHypoTreatmentMeal: True when the meal description matches a FavoriteFood marked isHypoTreatment.
    ///   - showMissedBolusNudge: Toggle. Returns false immediately when off.
    ///   - nudgedMealIds: In-memory dedup set — at most one nudge per meal.
    static func shouldNudge(
        meal: MealEntry,
        deliveries: [InsulinDelivery],
        now: Date,
        treatmentCycleActive: Bool,
        isHypoTreatmentMeal: Bool,
        showMissedBolusNudge: Bool,
        nudgedMealIds: Set<UUID>
    ) -> Bool {
        guard showMissedBolusNudge else { return false }
        guard !treatmentCycleActive else { return false }
        guard !isHypoTreatmentMeal else { return false }
        guard !nudgedMealIds.contains(meal.id) else { return false }
        guard (meal.carbsGrams ?? 0) >= carbsThresholdGrams else { return false }

        let pairedUnits = deliveries
            .filter {
                ($0.type == .mealBolus || $0.type == .snackBolus)
                    && abs($0.starts.timeIntervalSince(meal.timestamp)) <= pairingWindowSeconds
            }
            .reduce(0.0) { $0 + $1.units }

        return pairedUnits < minPairedBolusUnits
    }
}
