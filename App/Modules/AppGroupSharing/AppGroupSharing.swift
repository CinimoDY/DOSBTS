//
//  FreeAPS.swift
//  DOSBTS
//

import Combine
import Foundation
import WidgetKit

func appGroupSharingMiddleware() -> Middleware<DirectState, DirectAction> {
    return appGroupSharingMiddleware(service: LazyService<AppGroupSharingService>(initialization: {
        AppGroupSharingService()
    }))
}

private func appGroupSharingMiddleware(service: LazyService<AppGroupSharingService>) -> Middleware<DirectState, DirectAction> {
    return { state, action, _ in
        switch action {
        case .startup:
            service.value.clearAll()
            service.value.setApp(app: DirectConfig.appName, appVersion: "\(DirectConfig.appVersion) (\(DirectConfig.appBuild))")
            // Seed alarm profile data into the App Group on launch so the widget
            // resolves against the user's configured thresholds before the first
            // sensor tick lands. Without this, WidgetAlarmProfileSnapshot.resolve()
            // would hit its 8-key all-or-nothing guard and fall back to legacy
            // shared keys (which are never written, so render against hardcoded
            // 80/180 defaults).
            service.value.writeAlarmProfileData(state: state)

        case .selectConnection(id: _, connection: _):
            service.value.clearAll()

        case .setConnectionState(connectionState: let connectionState):
            service.value.setConnectionState(value: connectionState.localizedDescription)

        case .setSensor(sensor: let sensor, keepDevice: _):
            service.value.setSensor(sensor: sensor.type.localizedDescription, sensorState: sensor.state.localizedDescription, sensorConnectionState: state.connectionState.localizedDescription)

        case .setTransmitter(transmitter: let transmitter):
            service.value.setTransmitter(transmitter: transmitter.name, transmitterBattery: "\(transmitter.battery)%", transmitterHardware: transmitter.hardware?.description, transmitterFirmware: transmitter.firmware?.description)

        case .disconnectConnection:
            service.value.clearGlucoseValues()

        case .pairConnection:
            service.value.clearGlucoseValues()

        case .addBloodGlucose(glucoseValues: let glucoseValues):
            if let sensor = state.sensor {
                service.value.setSensor(sensor: sensor.type.localizedDescription, sensorState: sensor.state.localizedDescription, sensorConnectionState: state.connectionState.localizedDescription)
            } else {
                service.value.setSensor(sensor: nil, sensorState: nil, sensorConnectionState: nil)
            }

            if let transmitter = state.transmitter {
                service.value.setTransmitter(transmitter: transmitter.name, transmitterBattery: "\(transmitter.battery)%", transmitterHardware: transmitter.hardware?.description, transmitterFirmware: transmitter.firmware?.description)
            } else {
                service.value.setTransmitter(transmitter: nil, transmitterBattery: nil, transmitterHardware: nil, transmitterFirmware: nil)
            }

            guard let glucose = glucoseValues.last else {
                break
            }

            service.value.addBloodGlucose(glucoseValues: [glucose])

        case .addSensorGlucose(glucoseValues: let glucoseValues):
            if let sensor = state.sensor {
                service.value.setSensor(sensor: sensor.type.localizedDescription, sensorState: sensor.state.localizedDescription, sensorConnectionState: state.connectionState.localizedDescription)
            } else {
                service.value.setSensor(sensor: nil, sensorState: nil, sensorConnectionState: nil)
            }

            if let transmitter = state.transmitter {
                service.value.setTransmitter(transmitter: transmitter.name, transmitterBattery: "\(transmitter.battery)%", transmitterHardware: transmitter.hardware?.description, transmitterFirmware: transmitter.firmware?.description)
            } else {
                service.value.setTransmitter(transmitter: nil, transmitterBattery: nil, transmitterHardware: nil, transmitterFirmware: nil)
            }

            guard let glucose = glucoseValues.last else {
                break
            }

            guard glucose.type != .high else {
                break
            }

            service.value.addSensorGlucose(glucoseValues: [glucose])

            // Widget expanded data: TIR, IOB, last meal, sparkline
            // Capture values from state on main thread, write on background
            let tir = state.glucoseStatistics?.tir
            let iob = UserDefaults.shared.sharedIOB
            let todayMeal = state.mealEntryValues
                .filter { Calendar.current.isDateInToday($0.timestamp) }
                .max(by: { $0.timestamp < $1.timestamp })
            let glucoseValues = state.sensorGlucoseValues

            DispatchQueue.global(qos: .utility).async {
                service.value.setWidgetData(
                    tir: tir,
                    iob: iob,
                    lastMeal: todayMeal,
                    glucoseValues: glucoseValues
                )
            }

            service.value.writeAlarmProfileData(state: state)

        case .setDayAlarmHigh, .setDayAlarmLow,
             .setNightAlarmHigh, .setNightAlarmLow,
             .setNightScheduleStart, .setNightScheduleEnd:
            // Mirror profile data to the App Group suite so widget + Live Activity
            // see settings changes without waiting for the next 5-min sensor tick.
            // Reload widget timelines explicitly — GlucoseWidget's TimelineProvider
            // schedules a 15-minute reload by default; without an explicit kick the
            // user wouldn't see threshold/schedule edits until that interval expires.
            //
            // Volume setters (.setDay/NightAlarmVolume) are intentionally excluded:
            // volume is not rendered on the widget or Live Activity, and slider drags
            // dispatch many setter calls per second — mirroring on volume changes
            // burns the ActivityKit push budget without any user-visible benefit.
            service.value.writeAlarmProfileData(state: state)
            WidgetCenter.shared.reloadAllTimelines()

        default:
            break
        }

        return Empty().eraseToAnyPublisher()
    }
}

// MARK: - AppGroupSharingService

private class AppGroupSharingService {
    // MARK: Lifecycle

    init() {
        DirectLog.info("Create AppGroupSharingService")
    }

    // MARK: Internal

    func clearGlucoseValues() {
        UserDefaults.shared.sharedGlucose = nil
        UserDefaults.shared.sharedTIR = nil
        UserDefaults.shared.sharedIOB = nil
        UserDefaults.shared.sharedLastMealDescription = nil
        UserDefaults.shared.sharedLastMealCarbs = nil
        UserDefaults.shared.sharedLastMealTimestamp = nil
        UserDefaults.shared.sharedGlucoseSparkline = nil
    }

    func clearOthers() {
        UserDefaults.shared.sharedSensor = nil
        UserDefaults.shared.sharedSensorState = nil
        UserDefaults.shared.sharedSensorConnectionState = nil
        UserDefaults.shared.sharedTransmitter = nil
        UserDefaults.shared.sharedTransmitterBattery = nil
        UserDefaults.shared.sharedTransmitterHardware = nil
        UserDefaults.shared.sharedTransmitterFirmware = nil
    }

    func clearAll() {
        clearGlucoseValues()
        clearOthers()
    }

    func setApp(app: String?, appVersion: String?) {
        UserDefaults.shared.sharedApp = app
        UserDefaults.shared.sharedAppVersion = appVersion
    }

    func setSensor(sensor: String?, sensorState: String?, sensorConnectionState: String?) {
        UserDefaults.shared.sharedSensor = sensor
        UserDefaults.shared.sharedSensorState = sensorState
        UserDefaults.shared.sharedSensorConnectionState = sensorConnectionState
    }

    func setConnectionState(value: String?) {
        UserDefaults.shared.sharedSensorConnectionState = value
    }

    func setTransmitter(transmitter: String?, transmitterBattery: String?, transmitterHardware: String?, transmitterFirmware: String?) {
        UserDefaults.shared.sharedTransmitter = transmitter
        UserDefaults.shared.sharedTransmitterBattery = transmitterBattery
        UserDefaults.shared.sharedTransmitterHardware = transmitterHardware
        UserDefaults.shared.sharedTransmitterFirmware = transmitterFirmware
    }

    func setWidgetData(
        tir: Double?,
        iob: Double?,
        lastMeal: MealEntry?,
        glucoseValues: [SensorGlucose]
    ) {
        UserDefaults.shared.sharedTIR = tir
        UserDefaults.shared.sharedIOB = iob

        // Last meal
        UserDefaults.shared.sharedLastMealDescription = lastMeal?.mealDescription
        UserDefaults.shared.sharedLastMealCarbs = lastMeal?.carbsGrams
        UserDefaults.shared.sharedLastMealTimestamp = lastMeal?.timestamp

        // Sparkline: sample glucose at ~30-min intervals over last 6h
        let sixHoursAgo = Date().addingTimeInterval(-6 * 60 * 60)
        let recentGlucose = glucoseValues.filter { $0.timestamp >= sixHoursAgo }

        if recentGlucose.count >= 2 {
            let interval: TimeInterval = 30 * 60 // 30 minutes
            var sampled: [Int] = []
            guard let firstReading = recentGlucose.first else { return }
            var nextSampleTime = firstReading.timestamp

            for glucose in recentGlucose {
                if glucose.timestamp >= nextSampleTime {
                    sampled.append(glucose.glucoseValue)
                    nextSampleTime = glucose.timestamp.addingTimeInterval(interval)
                }
            }
            // Always include the most recent reading as the final point
            if let last = recentGlucose.last {
                sampled.append(last.glucoseValue)
            }
            UserDefaults.shared.sharedGlucoseSparkline = sampled
        } else {
            UserDefaults.shared.sharedGlucoseSparkline = nil
        }
    }

    func addBloodGlucose(glucoseValues: [BloodGlucose]) {
        let sharedValues = glucoseValues
            .map { $0.toFreeAPS() }
            .compactMap { $0 }

        guard let sharedValuesJson = try? JSONSerialization.data(withJSONObject: sharedValues) else {
            DirectLog.error("AppGroupSharing: failed to serialize shared blood-glucose payload (\(sharedValues.count) values) — widget will show stale data")
            return
        }

        UserDefaults.shared.sharedGlucose = sharedValuesJson
    }

    /// Mirrors the day/night alarm profile schedule and per-profile thresholds to
    /// `UserDefaults.shared` (App Group). Widget and Live Activity duplicate the
    /// resolution algorithm so they stay in sync without per-tick push churn.
    /// Uses raw key strings: the `UserDefaults` computed properties in
    /// `Library/Extensions/UserDefaults.swift` target `UserDefaults.standard`,
    /// and the App Group suite is a different store.
    func writeAlarmProfileData(state: DirectState) {
        UserDefaults.shared.set(state.dayAlarmHigh, forKey: AppGroupAlarmProfileKeys.dayAlarmHigh)
        UserDefaults.shared.set(state.dayAlarmLow, forKey: AppGroupAlarmProfileKeys.dayAlarmLow)
        UserDefaults.shared.set(state.nightAlarmHigh, forKey: AppGroupAlarmProfileKeys.nightAlarmHigh)
        UserDefaults.shared.set(state.nightAlarmLow, forKey: AppGroupAlarmProfileKeys.nightAlarmLow)
        UserDefaults.shared.set(state.nightStartHour, forKey: AppGroupAlarmProfileKeys.nightStartHour)
        UserDefaults.shared.set(state.nightStartMinute, forKey: AppGroupAlarmProfileKeys.nightStartMinute)
        UserDefaults.shared.set(state.nightEndHour, forKey: AppGroupAlarmProfileKeys.nightEndHour)
        UserDefaults.shared.set(state.nightEndMinute, forKey: AppGroupAlarmProfileKeys.nightEndMinute)
    }

    func addSensorGlucose(glucoseValues: [SensorGlucose]) {
        let sharedValues = glucoseValues
            .map { $0.toFreeAPS() }
            .compactMap { $0 }

        guard let sharedValuesJson = try? JSONSerialization.data(withJSONObject: sharedValues) else {
            DirectLog.error("AppGroupSharing: failed to serialize shared sensor-glucose payload (\(sharedValues.count) values) — widget will show stale data")
            return
        }

        UserDefaults.shared.sharedGlucose = sharedValuesJson
    }
}

// Internal (not fileprivate) so the payload-mapper tests can reach it via @testable import.
extension BloodGlucose {
    func toFreeAPS() -> [String: Any]? {
        let date = "/Date(" + Int64(floor(timestamp.toMillisecondsAsDouble() / 1000) * 1000).description + ")/"

        let freeAPSGlucose: [String: Any] = [
            "Value": glucoseValue,
            "Trend": SensorTrend.unknown.toNightscoutTrend(),
            "DT": date,
            "direction": SensorTrend.unknown.toNightscoutDirection(),
            "from": DirectConfig.projectName
        ]

        return freeAPSGlucose
    }
}

// Internal (not fileprivate) so the payload-mapper tests can reach it via @testable import.
extension SensorGlucose {
    func toFreeAPS() -> [String: Any]? {
        let date = "/Date(" + Int64(floor(timestamp.toMillisecondsAsDouble() / 1000) * 1000).description + ")/"

        let freeAPSGlucose: [String: Any] = [
            "Value": glucoseValue,
            "Trend": trend.toNightscoutTrend(),
            "DT": date,
            "direction": trend.toNightscoutDirection(),
            "from": DirectConfig.projectName
        ]

        return freeAPSGlucose
    }
}
