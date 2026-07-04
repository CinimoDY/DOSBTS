//
//  MissedBolusMiddleware.swift
//  DOSBTS
//

import Combine
import Foundation
import UserNotifications

// MARK: - Constants

private let nudgeNotificationBase = "missed-bolus-nudge"
private let graceIntervalSeconds: Double = 20 * 60

// MARK: - missedBolusNudgeMiddleware

/// Watches .addMealEntry and schedules a single nudge notification after a 20-min grace if
/// no paired meal/snack bolus (±15 min, ≥0.5 U) has been logged.
///
/// Cross-middleware: .addMealEntry is also handled by mealEntryStoreMiddleware and
/// favoriteFoodStoreMiddleware. .addInsulinDelivery is also handled by
/// insulinDeliveryStoreMiddleware and iobMiddleware.
func missedBolusNudgeMiddleware() -> Middleware<DirectState, DirectAction> {
    var scheduledMealIds = Set<UUID>()

    return { state, action, _ in
        switch action {
        case .addMealEntry(mealEntryValues: let meals):
            guard state.showMissedBolusNudge else { break }
            // treatmentLoggedAt is set by .logHypoTreatment before startTreatmentCycle fires,
            // so it catches the brief race window where treatmentCycleActive is still false.
            guard state.treatmentLoggedAt == nil else { break }

            let hypoDescriptions = Set(
                state.favoriteFoodValues
                    .filter { $0.isHypoTreatment }
                    .map { $0.mealDescription }
            )

            for meal in meals {
                guard MissedBolusDetector.shouldNudge(
                    meal: meal,
                    deliveries: state.insulinDeliveryValues,
                    now: Date(),
                    treatmentCycleActive: state.treatmentCycleActive,
                    isHypoTreatmentMeal: hypoDescriptions.contains(meal.mealDescription),
                    showMissedBolusNudge: state.showMissedBolusNudge,
                    nudgedMealIds: scheduledMealIds
                ) else { continue }

                scheduledMealIds.insert(meal.id)

                let content = UNMutableNotificationContent()
                content.title = LocalizedString("Meal Logged")
                content.body = LocalizedString("Meal logged — no bolus recorded. Forgot to log it, or still to dose?")
                content.interruptionLevel = .active

                let trigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: graceIntervalSeconds,
                    repeats: false
                )

                DirectNotifications.shared.addNotification(
                    identifier: "\(nudgeNotificationBase)-\(meal.id.uuidString)",
                    content: content,
                    trigger: trigger
                )

                DirectLog.info("MissedBolus: scheduled nudge for '\(meal.mealDescription)' in 20 min")
            }

        case .addInsulinDelivery(insulinDeliveryValues: let deliveries):
            // Cancel any pending nudge whose meal falls within the pairing window of this delivery.
            for delivery in deliveries {
                guard delivery.type == .mealBolus || delivery.type == .snackBolus else { continue }

                let pairedMeals = state.mealEntryValues.filter {
                    abs($0.timestamp.timeIntervalSince(delivery.starts)) <= MissedBolusDetector.pairingWindowSeconds
                }

                for meal in pairedMeals {
                    let identifier = "\(nudgeNotificationBase)-\(meal.id.uuidString)"
                    DirectNotifications.shared.removeNotification(identifier: identifier)
                    scheduledMealIds.remove(meal.id)
                    DirectLog.info("MissedBolus: cancelled nudge for '\(meal.mealDescription)' — bolus paired")
                }
            }

        default:
            break
        }

        return Empty().eraseToAnyPublisher()
    }
}
