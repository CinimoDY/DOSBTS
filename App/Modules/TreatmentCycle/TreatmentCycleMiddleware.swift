//
//  TreatmentCycleMiddleware.swift
//  DOSBTS
//

import Combine
import Foundation
import UserNotifications

private let recheckNotificationIdentifier = "treatment-recheck"

func treatmentCycleMiddleware() -> Middleware<DirectState, DirectAction> {
    return { state, action, _ in
        switch action {
        case .logHypoTreatment(favorite: let favorite, alarmFiredAt: let alarmFiredAt, overrideTimestamp: let overrideTimestamp):
            let mealEntry = favorite.toMealEntry()
            let treatmentLoggedAt = overrideTimestamp ?? Date()

            let treatmentEvent = TreatmentEvent(
                mealEntryId: mealEntry.id,
                alarmFiredAt: alarmFiredAt,
                treatmentLoggedAt: treatmentLoggedAt,
                treatmentType: favorite.mealDescription,
                glucoseAtTreatment: state.latestSensorGlucose?.glucoseValue ?? 0,
                countdownMinutes: state.hypoTreatmentWaitMinutes
            )

            // Cancel any existing recheck notification before scheduling new one (chained cycle safety)
            DirectNotifications.shared.removeNotification(identifier: recheckNotificationIdentifier)
            // The "Trending Low" alert has been acted on (DMNC-1560).
            DirectNotifications.shared.removeNotification(identifier: predictiveLowNotificationIdentifier)

            // Schedule recheck notification for when the countdown expires
            let content = UNMutableNotificationContent()
            content.title = LocalizedString("Treatment Recheck")
            content.body = LocalizedString("Time to recheck your glucose")
            content.sound = .default
            content.interruptionLevel = .timeSensitive

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: Double(state.hypoTreatmentWaitMinutes * 60),
                repeats: false
            )

            DirectNotifications.shared.addNotification(
                identifier: recheckNotificationIdentifier,
                content: content,
                trigger: trigger
            )

            DirectLog.info("Treatment cycle: logged treatment '\(favorite.mealDescription)', recheck in \(state.hypoTreatmentWaitMinutes) min")

            // Cross-middleware: .addMealEntry also handled by mealEntryStoreMiddleware and favoriteFoodStoreMiddleware
            return Publishers.Merge3(
                Just(DirectAction.addMealEntry(mealEntryValues: [mealEntry]))
                    .setFailureType(to: DirectError.self),
                Just(DirectAction.addTreatmentEvent(treatmentEvent: treatmentEvent))
                    .setFailureType(to: DirectError.self),
                Just(DirectAction.startTreatmentCycle)
                    .setFailureType(to: DirectError.self)
            ).eraseToAnyPublisher()

        // Cross-middleware: .addSensorGlucose is also handled by SensorConnector and GlucoseNotification middlewares
        case .addSensorGlucose(glucoseValues: let glucoseValues):
            guard state.treatmentCycleActive, !state.recheckDispatched else {
                break
            }

            guard let expiryDate = state.treatmentCycleCountdownExpiry else {
                break
            }

            // Only evaluate after the countdown has expired
            guard Date() >= expiryDate else {
                break
            }

            let glucoseValue = glucoseValues.last?.glucoseValue ?? state.latestSensorGlucose?.glucoseValue

            guard let glucose = glucoseValue else {
                break
            }

            if glucose >= state.alarmLow {
                DirectLog.info("Treatment cycle: glucose \(glucose) recovered above low threshold \(state.alarmLow)")
                return Just(DirectAction.treatmentCycleRecovered(glucoseValue: glucose))
                    .setFailureType(to: DirectError.self)
                    .eraseToAnyPublisher()
            } else {
                DirectLog.info("Treatment cycle: glucose \(glucose) still below low threshold \(state.alarmLow)")
                return Just(DirectAction.treatmentCycleStillLow(glucoseValue: glucose))
                    .setFailureType(to: DirectError.self)
                    .eraseToAnyPublisher()
            }

        case .dismissTreatmentCycle:
            DirectNotifications.shared.removeNotification(identifier: recheckNotificationIdentifier)
            DirectNotifications.shared.removeNotification(identifier: predictiveLowNotificationIdentifier)
            DirectLog.info("Treatment cycle: dismissed, cancelled recheck notification")

        case .endTreatmentCycle:
            DirectNotifications.shared.removeNotification(identifier: recheckNotificationIdentifier)
            DirectNotifications.shared.removeNotification(identifier: predictiveLowNotificationIdentifier)
            DirectLog.info("Treatment cycle: ended, cancelled recheck notification")

        case .setAppState(appState: let appState):
            guard appState == .active else {
                break
            }

            guard state.treatmentCycleActive else {
                break
            }

            guard let expiryDate = state.treatmentCycleCountdownExpiry else {
                // Defensive: active=true but expiry=nil means partial UserDefaults write (crash/kill).
                // Reset to safe state to prevent indefinite alarm suppression.
                DirectLog.warning("Treatment cycle: active but no countdown expiry — clearing corrupt state")
                return Just(DirectAction.dismissTreatmentCycle)
                    .setFailureType(to: DirectError.self)
                    .eraseToAnyPublisher()
            }

            // If countdown not yet expired, re-schedule the recheck notification with remaining time
            let remaining = expiryDate.timeIntervalSinceNow
            if remaining > 0 {
                let content = UNMutableNotificationContent()
                content.title = LocalizedString("Treatment Recheck")
                content.body = LocalizedString("Time to recheck your glucose")
                content.sound = .default
                content.interruptionLevel = .timeSensitive

                let trigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: remaining,
                    repeats: false
                )

                DirectNotifications.shared.addNotification(
                    identifier: recheckNotificationIdentifier,
                    content: content,
                    trigger: trigger
                )

                DirectLog.info("Treatment cycle: app became active, re-scheduled recheck in \(Int(remaining)) seconds")
            }
            // If countdown already expired, recheck will trigger on next .addSensorGlucose

        default:
            break
        }

        return Empty().eraseToAnyPublisher()
    }
}
