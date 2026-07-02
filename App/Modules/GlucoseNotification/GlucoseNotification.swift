//
//  GlucoseAlert.swift
//  DOSBTS
//

import Combine
import Foundation
import UIKit
import UserNotifications

func glucoseNotificationMiddleware() -> Middleware<DirectState, DirectAction> {
    return glucoseNotificationMiddleware(service: LazyService<GlucoseNotificationService>(initialization: {
        GlucoseNotificationService()
    }))
}

private func glucoseNotificationMiddleware(service: LazyService<GlucoseNotificationService>) -> Middleware<DirectState, DirectAction> {
    return { state, action, _ in
        switch action {
        case .setGlucoseUnit(unit: let unit):
            guard let glucose = state.latestSensorGlucose else {
                break
            }

            service.value.setGlucoseNotification(glucose: glucose, glucoseUnit: unit)

        case .addSensorGlucose(glucoseValues: let glucoseValues):
            guard let glucose = glucoseValues.last else {
                break
            }

            // --- Predictive Low Alarm (R1-R4, R8a-R8c) ---
            // Evaluates BEFORE the actual alarm check.
            // CRITICAL: Does NOT trigger autosnooze — actual alarm must still fire independently.
            // CRITICAL: Does NOT fire when treatment cycle is already active — prevents
            // activating treatmentCycleSnooze which would suppress the actual low alarm.
            predictiveCheck: if state.showPredictiveLowAlarm,
                !state.predictiveLowAlarmFired,
                !state.treatmentCycleActive, // Prevents snooze cascade + race/restart/oscillation issues
                glucose.glucoseValue >= state.alarmLow, // R4: only when still above threshold
                glucose.timestamp.timeIntervalSinceNow > -5 * 60 // R8b: reading <5 min old
            {
                // Compute smoothed minuteChange (average of last 3 with non-nil values)
                // Require at least 2 samples to avoid single-reading noise spikes
                let recentChanges = state.sensorGlucoseValues
                    .suffix(10)
                    .compactMap(\.minuteChange)
                    .suffix(3)

                guard recentChanges.count >= 2 else { break predictiveCheck }
                let smoothedChange = recentChanges.reduce(0, +) / Double(recentChanges.count)

                // R3: Linear extrapolation over 20 minutes
                let predictedGlucose = Double(glucose.glucoseValue) + (smoothedChange * 20.0)

                // R2: Fire if predicted to cross below alarmLow
                if predictedGlucose < Double(state.alarmLow) {
                    DirectLog.info("Predictive low alarm: current=\(glucose.glucoseValue), predicted=\(Int(predictedGlucose)), alarmLow=\(state.alarmLow)")

                    // Fire the predictive notification (for background/lock screen)
                    service.value.setPredictiveLowNotification(
                        glucose: glucose,
                        predictedGlucose: Int(predictedGlucose),
                        glucoseUnit: state.glucoseUnit,
                        alarmLow: state.alarmLow,
                        smoothedMinuteChange: smoothedChange
                    )

                    // R8a: NO autosnooze — return showTreatmentPrompt + flag, NOT setAlarmSnoozeUntil
                    return Publishers.Merge(
                        Just(DirectAction.showTreatmentPrompt(alarmFiredAt: Date()))
                            .setFailureType(to: DirectError.self),
                        Just(DirectAction.setPredictiveLowAlarmFired(fired: true))
                            .setFailureType(to: DirectError.self)
                    ).eraseToAnyPublisher()
                }
            }

            // R8c: Clear predictive flag when glucose rises above alarmLow + 10 (episode resolved).
            // Also clear when actual low alarm fires (prevents flag staying stuck after partial recovery).
            // Uses a deferred action array instead of early return so normal notification logic still runs.
            var deferredActions: [DirectAction] = []

            if state.predictiveLowAlarmFired {
                if glucose.glucoseValue >= state.alarmLow + 10 {
                    // Episode resolved — glucose recovered
                    deferredActions.append(.setPredictiveLowAlarmFired(fired: false))
                } else if glucose.glucoseValue < state.alarmLow {
                    // Actual low — clear flag so prediction can re-fire on next episode
                    deferredActions.append(.setPredictiveLowAlarmFired(fired: false))
                }
            }

            let alarm = state.isAlarm(glucoseValue: glucose.glucoseValue)
            DirectLog.info("alarm: \(alarm)")
            
            let isSnoozed = state.isSnoozed(alarm: alarm)
            DirectLog.info("isSnoozed: \(isSnoozed)")

            // Cross-middleware: reads treatmentCycleActive and treatmentCycleSnoozeUntil set by treatmentCycleMiddleware.
            // Treatment cycle suppresses low alarm sound (but not banners).
            // Critical-low floor (alarmLow - 15 mg/dL) breaks through.
            let isTreatmentSnoozed = state.treatmentCycleActive &&
                (state.treatmentCycleSnoozeUntil.map { Date() < $0 } ?? false)
            DirectLog.info("isTreatmentSnoozed: \(isTreatmentSnoozed)")

            if alarm == .lowAlarm {
                DirectLog.info("Glucose alert, low: \(glucose.glucoseValue) < \(state.alarmLow)")

                if state.alarmGlucoseNotification {
                    service.value.setLowGlucoseNotification(glucose: glucose, glucoseUnit: state.glucoseUnit, isSnoozed: isSnoozed)
                }

                // Critical-low floor: if glucose is more than 15 mg/dL below alarmLow,
                // break through treatment snooze (safety override). Helper lives in
                // Library/Content/AlarmProfile.swift so tests can verify the
                // decision directly without re-asserting the arithmetic inline.
                let isCriticalLow = isCriticalLow(glucoseValue: glucose.glucoseValue, alarmLow: state.alarmLow)

                if !isSnoozed && (!isTreatmentSnoozed || isCriticalLow) {
                    if state.hasLowGlucoseAlarm {
                        service.value.setLowGlucoseAlarm(sound: state.lowGlucoseAlarmSound, volume: state.alarmVolume, ignoreMute: state.ignoreMute)
                    }

                    let snoozeAction = Just(DirectAction.setAlarmSnoozeUntil(untilDate: Date().addingTimeInterval(5 * 60).toRounded(on: 1, .minute), autosnooze: true))
                        .setFailureType(to: DirectError.self)
                    if let deferredAction = deferredActions.first {
                        return Publishers.Merge(
                            snoozeAction,
                            Just(deferredAction).setFailureType(to: DirectError.self)
                        ).eraseToAnyPublisher()
                    }
                    return snoozeAction.eraseToAnyPublisher()
                }

            } else if alarm == .highAlarm {
                DirectLog.info("Glucose alert, high: \(glucose.glucoseValue) > \(state.alarmHigh)")

                if state.alarmGlucoseNotification {
                    service.value.setHighGlucoseNotification(glucose: glucose, glucoseUnit: state.glucoseUnit, isSnoozed: isSnoozed)
                }

                if !isSnoozed {
                    if state.hasHighGlucoseAlarm {
                        service.value.setHighGlucoseAlarm(sound: state.highGlucoseAlarmSound, volume: state.alarmVolume, ignoreMute: state.ignoreMute)
                    }

                    return Just(.setAlarmSnoozeUntil(untilDate: Date().addingTimeInterval(5 * 60).toRounded(on: 1, .minute), autosnooze: true))
                        .setFailureType(to: DirectError.self)
                        .eraseToAnyPublisher()
                }

            } else if state.normalGlucoseNotification {
                service.value.setGlucoseNotification(glucose: glucose, glucoseUnit: state.glucoseUnit)
            } else {
                service.value.clear()
            }

            // Emit any deferred predictive alarm actions (flag clear) that weren't merged above
            if let deferredAction = deferredActions.first {
                return Just(deferredAction)
                    .setFailureType(to: DirectError.self)
                    .eraseToAnyPublisher()
            }

        default:
            break
        }

        return Empty().eraseToAnyPublisher()
    }
}

// MARK: - GlucoseNotificationService

private class GlucoseNotificationService {
    // MARK: Lifecycle

    init() {
        DirectLog.info("Create GlucoseNotificationService")
    }

    // MARK: Internal

    enum Identifier: String {
        case sensorGlucoseAlarm = "libre-direct.notifications.sensor-glucose-alarm"
    }

    func clear() {
        UNUserNotificationCenter.current().setBadgeCount(0, withCompletionHandler: nil)
        DirectNotifications.shared.removeNotification(identifier: Identifier.sensorGlucoseAlarm.rawValue)
    }

    func setGlucoseNotification(glucose: SensorGlucose, glucoseUnit: GlucoseUnit) {
        DirectNotifications.shared.ensureCanSendNotification { state in
            DirectLog.info("Glucose info, state: \(state)")

            guard state != .none else {
                return
            }

            let notification = UNMutableNotificationContent()
            notification.sound = .none
            notification.interruptionLevel = .passive

            if glucoseUnit == .mgdL {
                notification.badge = glucose.glucoseValue as NSNumber
            } else {
                notification.badge = glucose.glucoseValue.asRoundedMmolL as NSNumber
            }

            notification.title = String(format: LocalizedString("Blood glucose: %1$@"), glucose.glucoseValue.asGlucose(glucoseUnit: glucoseUnit, withUnit: true))
            notification.body = String(format: LocalizedString("Your current glucose is %1$@ (%2$@)."),
                                       glucose.glucoseValue.asGlucose(glucoseUnit: glucoseUnit, withUnit: true),
                                       glucose.minuteChange?.asMinuteChange(glucoseUnit: glucoseUnit) ?? "?"
            )

            DirectNotifications.shared.addNotification(identifier: Identifier.sensorGlucoseAlarm.rawValue, content: notification)
        }
    }

    func setLowGlucoseAlarm(sound: NotificationSound, volume: Float, ignoreMute: Bool) {
        DirectNotifications.shared.playSound(sound: sound, volume: volume, ignoreMute: ignoreMute)
    }

    func setLowGlucoseNotification(glucose: SensorGlucose, glucoseUnit: GlucoseUnit, isSnoozed: Bool) {
        DirectNotifications.shared.ensureCanSendNotification { state in
            DirectLog.info("Glucose alert, state: \(state)")

            guard state != .none else {
                return
            }

            let notification = UNMutableNotificationContent()
            notification.sound = .none
            var userInfo = self.actions
            userInfo["alarmFiredAt"] = Date().timeIntervalSince1970
            notification.userInfo = userInfo
            notification.interruptionLevel = isSnoozed ? .passive : .timeSensitive
            notification.categoryIdentifier = "lowGlucoseAlarm"

            if glucoseUnit == .mgdL {
                notification.badge = glucose.glucoseValue as NSNumber
            } else {
                notification.badge = glucose.glucoseValue.asRoundedMmolL as NSNumber
            }

            notification.title = LocalizedString("Alert, low blood glucose")
            notification.body = String(format: LocalizedString("Your glucose %1$@ (%2$@) is dangerously low. With sweetened drinks or dextrose, blood glucose levels can often return to normal."),
                                       glucose.glucoseValue.asGlucose(glucoseUnit: glucoseUnit, withUnit: true),
                                       glucose.minuteChange?.asMinuteChange(glucoseUnit: glucoseUnit) ?? "?"
            )

            DirectNotifications.shared.addNotification(identifier: Identifier.sensorGlucoseAlarm.rawValue, content: notification)
        }
    }

    func setPredictiveLowNotification(glucose: SensorGlucose, predictedGlucose: Int, glucoseUnit: GlucoseUnit, alarmLow: Int, smoothedMinuteChange: Double) {
        DirectNotifications.shared.ensureCanSendNotification { state in
            guard state != .none else { return }

            let notification = UNMutableNotificationContent()
            notification.sound = .default // Softer than the actual low alarm
            var userInfo = self.actions
            userInfo["alarmFiredAt"] = Date().timeIntervalSince1970
            notification.userInfo = userInfo
            notification.interruptionLevel = .timeSensitive
            notification.categoryIdentifier = "predictiveLowAlarm"

            if glucoseUnit == .mgdL {
                notification.badge = glucose.glucoseValue as NSNumber
            } else {
                notification.badge = glucose.glucoseValue.asRoundedMmolL as NSNumber
            }

            // Use the smoothed minuteChange that triggered the alarm (consistent with prediction logic)
            let minutesToCross: Int
            if smoothedMinuteChange < 0 {
                minutesToCross = Int(Double(alarmLow - glucose.glucoseValue) / smoothedMinuteChange)
            } else {
                minutesToCross = 20
            }

            notification.title = LocalizedString("Trending Low")
            notification.body = String(format: LocalizedString("Glucose %1$@ predicted to drop below %2$@ in ~%3$d minutes. Eat now to prevent a low."),
                                       glucose.glucoseValue.asGlucose(glucoseUnit: glucoseUnit, withUnit: true),
                                       alarmLow.asGlucose(glucoseUnit: glucoseUnit, withUnit: true),
                                       minutesToCross
            )

            DirectNotifications.shared.addNotification(identifier: Identifier.sensorGlucoseAlarm.rawValue + ".predictive", content: notification)
        }
    }

    func setHighGlucoseAlarm(sound: NotificationSound, volume: Float, ignoreMute: Bool) {
        DirectNotifications.shared.playSound(sound: sound, volume: volume, ignoreMute: ignoreMute)
    }

    func setHighGlucoseNotification(glucose: SensorGlucose, glucoseUnit: GlucoseUnit, isSnoozed: Bool) {
        DirectNotifications.shared.ensureCanSendNotification { state in
            DirectLog.info("Glucose alert, state: \(state)")

            guard state != .none else {
                return
            }

            let notification = UNMutableNotificationContent()
            notification.sound = .none
            notification.userInfo = self.actions
            notification.interruptionLevel = isSnoozed ? .passive : .timeSensitive

            if glucoseUnit == .mgdL {
                notification.badge = glucose.glucoseValue as NSNumber
            } else {
                notification.badge = glucose.glucoseValue.asRoundedMmolL as NSNumber
            }

            notification.title = LocalizedString("Alert, high glucose")
            notification.body = String(format: LocalizedString("Your glucose %1$@ (%2$@) is dangerously high and needs to be treated."),
                                       glucose.glucoseValue.asGlucose(glucoseUnit: glucoseUnit, withUnit: true),
                                       glucose.minuteChange?.asMinuteChange(glucoseUnit: glucoseUnit) ?? "?"
            )

            DirectNotifications.shared.addNotification(identifier: Identifier.sensorGlucoseAlarm.rawValue, content: notification)
        }
    }

    // MARK: Private

    private let actions: [AnyHashable: Any] = [
        "action": "snooze"
    ]
}

private extension Int {
    var asRoundedMmolL: Double {
        let value = Double(self) * GlucoseUnit.exchangeRate
        let divisor = pow(10.0, Double(1))

        return round(value * divisor) / divisor
    }
}
