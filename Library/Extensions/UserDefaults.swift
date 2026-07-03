//
//  UserDefaults.swift
//  DOSBTS
//

import Foundation

// MARK: - Keys

private enum Keys: String {
    case appSerial = "libre-direct.settings.app-serial"
    case alarmHigh = "libre-direct.settings.alarm-high"
    case alarmLow = "libre-direct.settings.alarm-low"
    case alarmVolume = "libre-direct.settings.alarm-volume"
    case appleHealthExport = "libre-direct.settings.apple-health-export"
    case appleHealthImport = "libre-direct.settings.apple-health-import"
    case healthImportExcludedSources = "libre-direct.settings.health-import-excluded-sources"
    case bellmanAlarm = "libre-direct.settings.bellman-alarm"
    case calendarExport = "libre-direct.settings.calendar-export"
    case chartShowLines = "libre-direct.settings.chart-show-lines"
    case chartZoomLevel = "libre-direct.settings.chart-zoom-level"
    case connectionAlarmSound = "libre-direct.settings.connection-alarm-sound"
    case connectionPeripheralUUID = "libre-direct.sensor-ble-connection.peripheral-uuid"
    case customCalibration = "libre-direct.settings.custom-calibration"
    case expiringAlarmSound = "libre-direct.settings.expiring-alarm-sound"
    case normalGlucoseNotification = "libre-direct.settings.normal-glucose-notification"
    case alarmGlucoseNotification = "libre-direct.settings.alarm-glucose-notification"
    case glucoseLiveActivity = "libre-direct.settings.glucose-live-activity"
    case glucoseUnit = "libre-direct.settings.glucose-unit"
    case highGlucoseAlarmSound = "libre-direct.settings.high-glucose-alarm-sound"
    case ignoreMute = "libre-direct.settings.ignore-mute"
    case isConnectionPaired = "libre-direct.settings.is-paired"
    case latestBloodGlucose = "libre-direct.settings.latest-blood-glucose"
    case latestSensorError = "libre-direct.settings.latest-sensor-error"
    case latestSensorGlucose = "libre-direct.settings.latest-sensor-glucose"
    case latestInsulinDelivery = "libre-direct.settings.latest-insulin-delivery"
    case lowGlucoseAlarmSound = "libre-direct.settings.low-glucose-alarm-sound"
    case nightscoutApiSecret = "libre-direct.settings.nightscout-api-secret"
    case nightscoutUpload = "libre-direct.settings.nightscout-upload-enabled"
    case nightscoutURL = "libre-direct.settings.nightscout-host"
    case readGlucose = "libre-direct.settings.read-glucose"
    case selectedCalendarTarget = "libre-direct.settings.selected-calendar-target"
    case selectedConnectionID = "libre-direct.settings.selected-connection-id"
    case sensor = "libre-direct.settings.sensor"
    case sensorInterval = "libre-direct.settings.sensor-interval"
    case sharedApp = "glucosedirect--app"
    case sharedAppVersion = "glucosedirect--app-version"
    case sharedGlucose = "latestReadings"
    case sharedSensor = "glucosedirect--sensor"
    case sharedSensorConnectionState = "glucosedirect--sensor-connection-state"
    case sharedSensorState = "glucosedirect--sensor-state"
    case sharedTransmitter = "glucosedirect--transmitter"
    case sharedTransmitterBattery = "glucosedirect--transmitter-battery"
    case sharedTransmitterFirmware = "glucosedirect--transmitter-firmware"
    case sharedTransmitterHardware = "glucosedirect--transmitter-hardware"
    case transmitter = "libre-direct.settings.transmitter"
    case showAnnotations = "libre-direct.settings.show-annotations"
    case showSmoothedGlucose = "libre-direct.settings.smooth-chart-values"
    case showInsulinInput = "libre-direct.settings.show-insulin-delivery-input"
    case showScanlines = "libre-direct.settings.show-scanlines"
    case aiConsentFoodPhoto = "libre-direct.settings.ai-consent-food-photo"
    case hasSeenBGRelocationHint = "libre-direct.settings.has-seen-bg-relocation-hint"
    case appOpenCount = "libre-direct.settings.app-open-count"
    case appOpenCountFirstRecordedAt = "libre-direct.settings.app-open-count-first-recorded-at"
    case aiConsentDailyDigest = "libre-direct.settings.ai-consent-daily-digest"
    case claudeAPIKeyValid = "libre-direct.settings.claude-api-key-valid"
    case thumbCalibrationMM = "libre-direct.settings.thumb-calibration-mm"
    case servingPresets = "libre-direct.settings.serving-presets"
    case treatmentCycleActive = "libre-direct.settings.treatment-cycle-active"
    case alarmFiredAt = "libre-direct.settings.alarm-fired-at"
    case treatmentLoggedAt = "libre-direct.settings.treatment-logged-at"
    case treatmentCycleCountdownExpiry = "libre-direct.settings.treatment-cycle-countdown-expiry"
    case treatmentCycleSnoozeUntil = "libre-direct.settings.treatment-cycle-snooze-until"
    case hypoTreatmentWaitMinutes = "libre-direct.settings.hypo-treatment-wait-minutes"
    case showPredictiveLowAlarm = "libre-direct.settings.show-predictive-low-alarm"
    case showHeartRateOverlay = "libre-direct.settings.show-heart-rate-overlay"
    case markerLanePosition = "libre-direct.settings.marker-lane-position"
    case bolusInsulinPreset = "libre-direct.settings.bolus-insulin-preset"
    case basalDIAMinutes = "libre-direct.settings.basal-dia-minutes"
    case showSplitIOB = "libre-direct.settings.show-split-iob"
    case showCelebrations = "libre-direct.settings.show-celebrations"
    case tightControlStreakCount = "libre-direct.settings.tight-control-streak-count"
    case tightControlLastCelebratedStreakStart = "libre-direct.settings.tight-control-last-celebrated-streak-start"
    case tightControlPendingCelebrationCount = "libre-direct.settings.tight-control-pending-celebration-count"

    // What's New / changelog (DMNC-1147)
    case lastSeenBuild = "libre-direct.changelog.last-seen-build"

    // Day/Night alarm profiles
    case dayAlarmHigh = "libre-direct.settings.day-alarm-high"
    case dayAlarmLow = "libre-direct.settings.day-alarm-low"
    case dayAlarmVolume = "libre-direct.settings.day-alarm-volume"
    case nightAlarmHigh = "libre-direct.settings.night-alarm-high"
    case nightAlarmLow = "libre-direct.settings.night-alarm-low"
    case nightAlarmVolume = "libre-direct.settings.night-alarm-volume"
    case nightStartHour = "libre-direct.settings.night-start-hour"
    case nightStartMinute = "libre-direct.settings.night-start-minute"
    case nightEndHour = "libre-direct.settings.night-end-hour"
    case nightEndMinute = "libre-direct.settings.night-end-minute"

    // Daily digest reminder
    case dailyDigestReminderHour = "libre-direct.settings.daily-digest-reminder-hour"
    case dailyDigestReminderMinute = "libre-direct.settings.daily-digest-reminder-minute"

    // Ratio Lab
    case confirmedICR = "libre-direct.settings.confirmed-icr"

    // Widget shared data (App Group)
    case sharedTIR = "glucosedirect--tir"
    case sharedIOB = "glucosedirect--iob"
    case sharedLastMealDescription = "glucosedirect--last-meal-description"
    case sharedLastMealCarbs = "glucosedirect--last-meal-carbs"
    case sharedLastMealTimestamp = "glucosedirect--last-meal-timestamp"
    case sharedGlucoseSparkline = "glucosedirect--glucose-sparkline"
}

extension UserDefaults {
    var appSerial: String {
        if let serial = string(forKey: Keys.appSerial.rawValue) {
            return serial
        }

        let newSerial = UUID().uuidString

        set(newSerial, forKey: Keys.appSerial.rawValue)

        return newSerial
    }

    var alarmHigh: Int {
        get {
            if object(forKey: Keys.alarmHigh.rawValue) != nil {
                return integer(forKey: Keys.alarmHigh.rawValue)
            }

            return 180
        }
        set {
            set(newValue, forKey: Keys.alarmHigh.rawValue)
        }
    }

    var alarmLow: Int {
        get {
            if object(forKey: Keys.alarmLow.rawValue) != nil {
                return integer(forKey: Keys.alarmLow.rawValue)
            }

            return 80
        }
        set {
            set(newValue, forKey: Keys.alarmLow.rawValue)
        }
    }

    var alarmVolume: Float {
        get {
            if object(forKey: Keys.alarmVolume.rawValue) != nil {
                return float(forKey: Keys.alarmVolume.rawValue)
            }

            return 0.2
        }
        set {
            set(newValue, forKey: Keys.alarmVolume.rawValue)
        }
    }

    var appleHealthExport: Bool {
        get {
            if object(forKey: Keys.appleHealthExport.rawValue) != nil {
                return bool(forKey: Keys.appleHealthExport.rawValue)
            }

            return false
        }
        set {
            set(newValue, forKey: Keys.appleHealthExport.rawValue)
        }
    }

    var appleHealthImport: Bool {
        get {
            if object(forKey: Keys.appleHealthImport.rawValue) != nil {
                return bool(forKey: Keys.appleHealthImport.rawValue)
            }

            return false
        }
        set {
            set(newValue, forKey: Keys.appleHealthImport.rawValue)
        }
    }

    var healthImportExcludedSources: [String] {
        get {
            return stringArray(forKey: Keys.healthImportExcludedSources.rawValue) ?? []
        }
        set {
            set(newValue, forKey: Keys.healthImportExcludedSources.rawValue)
        }
    }

    var bellmanAlarm: Bool {
        get {
            if object(forKey: Keys.bellmanAlarm.rawValue) != nil {
                return bool(forKey: Keys.bellmanAlarm.rawValue)
            }

            return false
        }
        set {
            set(newValue, forKey: Keys.bellmanAlarm.rawValue)
        }
    }

    var ignoreMute: Bool {
        get {
            if object(forKey: Keys.ignoreMute.rawValue) != nil {
                return bool(forKey: Keys.ignoreMute.rawValue)
            }

            return false
        }
        set {
            set(newValue, forKey: Keys.ignoreMute.rawValue)
        }
    }

    var appleCalendarExport: Bool {
        get {
            if object(forKey: Keys.calendarExport.rawValue) != nil {
                return bool(forKey: Keys.calendarExport.rawValue)
            }

            return false
        }
        set {
            set(newValue, forKey: Keys.calendarExport.rawValue)
        }
    }

    var chartShowLines: Bool {
        get {
            if object(forKey: Keys.chartShowLines.rawValue) != nil {
                return bool(forKey: Keys.chartShowLines.rawValue)
            }

            return false
        }
        set {
            set(newValue, forKey: Keys.chartShowLines.rawValue)
        }
    }

    var chartZoomLevel: Int {
        get {
            if object(forKey: Keys.chartZoomLevel.rawValue) != nil {
                return integer(forKey: Keys.chartZoomLevel.rawValue)
            }

            return 3
        }
        set {
            set(newValue, forKey: Keys.chartZoomLevel.rawValue)
        }
    }

    var connectionPeripheralUUID: String? {
        get {
            return string(forKey: Keys.connectionPeripheralUUID.rawValue)
        }
        set {
            if let newValue = newValue {
                setValue(newValue, forKey: Keys.connectionPeripheralUUID.rawValue)
            } else {
                removeObject(forKey: Keys.connectionPeripheralUUID.rawValue)
            }
        }
    }

    var connectionAlarmSound: NotificationSound {
        get {
            if let soundRawValue = object(forKey: Keys.connectionAlarmSound.rawValue) as? String, let sound = NotificationSound(rawValue: soundRawValue) {
                return sound
            }

            return .alarm
        }
        set {
            set(newValue.rawValue, forKey: Keys.connectionAlarmSound.rawValue)
        }
    }

    var customCalibration: [CustomCalibration] {
        get {
            return getArray(forKey: Keys.customCalibration.rawValue) ?? []
        }
        set {
            setArray(newValue, forKey: Keys.customCalibration.rawValue)
        }
    }

    var expiringAlarmSound: NotificationSound {
        get {
            if let soundRawValue = object(forKey: Keys.expiringAlarmSound.rawValue) as? String, let sound = NotificationSound(rawValue: soundRawValue) {
                return sound
            }

            return .expiring
        }
        set {
            set(newValue.rawValue, forKey: Keys.expiringAlarmSound.rawValue)
        }
    }

    var highGlucoseAlarmSound: NotificationSound {
        get {
            if let soundRawValue = object(forKey: Keys.highGlucoseAlarmSound.rawValue) as? String, let sound = NotificationSound(rawValue: soundRawValue) {
                return sound
            }

            return .alarm
        }
        set {
            set(newValue.rawValue, forKey: Keys.highGlucoseAlarmSound.rawValue)
        }
    }

    var lowGlucoseAlarmSound: NotificationSound {
        get {
            if let soundRawValue = object(forKey: Keys.lowGlucoseAlarmSound.rawValue) as? String, let sound = NotificationSound(rawValue: soundRawValue) {
                return sound
            }

            return .alarm
        }
        set {
            set(newValue.rawValue, forKey: Keys.lowGlucoseAlarmSound.rawValue)
        }
    }

    var normalGlucoseNotification: Bool {
        get {
            if object(forKey: Keys.normalGlucoseNotification.rawValue) != nil {
                return bool(forKey: Keys.normalGlucoseNotification.rawValue)
            }

            return true
        }
        set {
            set(newValue, forKey: Keys.normalGlucoseNotification.rawValue)
        }
    }

    var alarmGlucoseNotification: Bool {
        get {
            if object(forKey: Keys.alarmGlucoseNotification.rawValue) != nil {
                return bool(forKey: Keys.alarmGlucoseNotification.rawValue)
            }

            return normalGlucoseNotification
        }
        set {
            set(newValue, forKey: Keys.alarmGlucoseNotification.rawValue)
        }
    }

    var glucoseLiveActivity: Bool {
        get {
            if object(forKey: Keys.glucoseLiveActivity.rawValue) != nil {
                return bool(forKey: Keys.glucoseLiveActivity.rawValue)
            }

            return false
        }
        set {
            set(newValue, forKey: Keys.glucoseLiveActivity.rawValue)
        }
    }

    var glucoseUnit: GlucoseUnit? {
        get {
            if let glucoseUnitValue = object(forKey: Keys.glucoseUnit.rawValue) as? String {
                return GlucoseUnit(rawValue: glucoseUnitValue)!
            }

            return nil
        }
        set {
            if let newValue = newValue {
                set(newValue.rawValue, forKey: Keys.glucoseUnit.rawValue)
            } else {
                removeObject(forKey: Keys.glucoseUnit.rawValue)
            }
        }
    }

    var isConnectionPaired: Bool {
        get {
            if object(forKey: Keys.isConnectionPaired.rawValue) != nil {
                return bool(forKey: Keys.isConnectionPaired.rawValue)
            }

            return false
        }
        set {
            set(newValue, forKey: Keys.isConnectionPaired.rawValue)
        }
    }

    var latestBloodGlucose: BloodGlucose? {
        get {
            return getObject(forKey: Keys.latestBloodGlucose.rawValue)
        }
        set {
            if let newValue = newValue {
                setObject(newValue, forKey: Keys.latestBloodGlucose.rawValue)
            } else {
                removeObject(forKey: Keys.latestBloodGlucose.rawValue)
            }
        }
    }

    var latestSensorGlucose: SensorGlucose? {
        get {
            return getObject(forKey: Keys.latestSensorGlucose.rawValue)
        }
        set {
            if let newValue = newValue {
                setObject(newValue, forKey: Keys.latestSensorGlucose.rawValue)
            } else {
                removeObject(forKey: Keys.latestSensorGlucose.rawValue)
            }
        }
    }

    var latestSensorError: SensorError? {
        get {
            return getObject(forKey: Keys.latestSensorError.rawValue)
        }
        set {
            if let newValue = newValue {
                setObject(newValue, forKey: Keys.latestSensorError.rawValue)
            } else {
                removeObject(forKey: Keys.latestSensorError.rawValue)
            }
        }
    }

    var latestInsulinDelivery: InsulinDelivery? {
        get {
            return getObject(forKey: Keys.latestInsulinDelivery.rawValue)
        }
        set {
            if let newValue = newValue {
                setObject(newValue, forKey: Keys.latestInsulinDelivery.rawValue)
            } else {
                removeObject(forKey: Keys.latestInsulinDelivery.rawValue)
            }
        }
    }

    var sharedGlucose: Data? {
        get {
            return data(forKey: Keys.sharedGlucose.rawValue)
        }
        set {
            if let newValue = newValue {
                set(newValue, forKey: Keys.sharedGlucose.rawValue)
            } else {
                removeObject(forKey: Keys.sharedGlucose.rawValue)
            }
        }
    }

    var sharedSensor: String? {
        get {
            return string(forKey: Keys.sharedSensor.rawValue)
        }
        set {
            if let newValue = newValue {
                set(newValue, forKey: Keys.sharedSensor.rawValue)
            } else {
                removeObject(forKey: Keys.sharedSensor.rawValue)
            }
        }
    }

    var sharedSensorState: String? {
        get {
            return string(forKey: Keys.sharedSensorState.rawValue)
        }
        set {
            if let newValue = newValue {
                set(newValue, forKey: Keys.sharedSensorState.rawValue)
            } else {
                removeObject(forKey: Keys.sharedSensorState.rawValue)
            }
        }
    }

    var sharedSensorConnectionState: String? {
        get {
            return string(forKey: Keys.sharedSensorConnectionState.rawValue)
        }
        set {
            if let newValue = newValue {
                set(newValue, forKey: Keys.sharedSensorConnectionState.rawValue)
            } else {
                removeObject(forKey: Keys.sharedSensorConnectionState.rawValue)
            }
        }
    }

    var sharedApp: String? {
        get {
            return string(forKey: Keys.sharedApp.rawValue)
        }
        set {
            if let newValue = newValue {
                set(newValue, forKey: Keys.sharedApp.rawValue)
            } else {
                removeObject(forKey: Keys.sharedApp.rawValue)
            }
        }
    }

    var sharedAppVersion: String? {
        get {
            return string(forKey: Keys.sharedAppVersion.rawValue)
        }
        set {
            if let newValue = newValue {
                set(newValue, forKey: Keys.sharedAppVersion.rawValue)
            } else {
                removeObject(forKey: Keys.sharedAppVersion.rawValue)
            }
        }
    }

    var sharedTransmitter: String? {
        get {
            return string(forKey: Keys.sharedTransmitter.rawValue)
        }
        set {
            if let newValue = newValue {
                set(newValue, forKey: Keys.sharedTransmitter.rawValue)
            } else {
                removeObject(forKey: Keys.sharedTransmitter.rawValue)
            }
        }
    }

    var sharedTransmitterBattery: String? {
        get {
            return string(forKey: Keys.sharedTransmitterBattery.rawValue)
        }
        set {
            if let newValue = newValue {
                set(newValue, forKey: Keys.sharedTransmitterBattery.rawValue)
            } else {
                removeObject(forKey: Keys.sharedTransmitterBattery.rawValue)
            }
        }
    }

    var sharedTransmitterHardware: String? {
        get {
            return string(forKey: Keys.sharedTransmitterHardware.rawValue)
        }
        set {
            if let newValue = newValue {
                set(newValue, forKey: Keys.sharedTransmitterHardware.rawValue)
            } else {
                removeObject(forKey: Keys.sharedTransmitterHardware.rawValue)
            }
        }
    }

    var sharedTransmitterFirmware: String? {
        get {
            return string(forKey: Keys.sharedTransmitterFirmware.rawValue)
        }
        set {
            if let newValue = newValue {
                set(newValue, forKey: Keys.sharedTransmitterFirmware.rawValue)
            } else {
                removeObject(forKey: Keys.sharedTransmitterFirmware.rawValue)
            }
        }
    }

    var sharedTIR: Double? {
        get {
            return object(forKey: Keys.sharedTIR.rawValue) as? Double
        }
        set {
            if let newValue = newValue {
                set(newValue, forKey: Keys.sharedTIR.rawValue)
            } else {
                removeObject(forKey: Keys.sharedTIR.rawValue)
            }
        }
    }

    var sharedIOB: Double? {
        get {
            return object(forKey: Keys.sharedIOB.rawValue) as? Double
        }
        set {
            if let newValue = newValue {
                set(newValue, forKey: Keys.sharedIOB.rawValue)
            } else {
                removeObject(forKey: Keys.sharedIOB.rawValue)
            }
        }
    }

    var sharedLastMealDescription: String? {
        get {
            return string(forKey: Keys.sharedLastMealDescription.rawValue)
        }
        set {
            if let newValue = newValue {
                set(newValue, forKey: Keys.sharedLastMealDescription.rawValue)
            } else {
                removeObject(forKey: Keys.sharedLastMealDescription.rawValue)
            }
        }
    }

    var sharedLastMealCarbs: Double? {
        get {
            return object(forKey: Keys.sharedLastMealCarbs.rawValue) as? Double
        }
        set {
            if let newValue = newValue {
                set(newValue, forKey: Keys.sharedLastMealCarbs.rawValue)
            } else {
                removeObject(forKey: Keys.sharedLastMealCarbs.rawValue)
            }
        }
    }

    var sharedLastMealTimestamp: Date? {
        get {
            return object(forKey: Keys.sharedLastMealTimestamp.rawValue) as? Date
        }
        set {
            if let newValue = newValue {
                set(newValue, forKey: Keys.sharedLastMealTimestamp.rawValue)
            } else {
                removeObject(forKey: Keys.sharedLastMealTimestamp.rawValue)
            }
        }
    }

    /// Sparkline data: sampled glucose values (mg/dL) at ~30-min intervals, last 6h
    var sharedGlucoseSparkline: [Int]? {
        get {
            return array(forKey: Keys.sharedGlucoseSparkline.rawValue) as? [Int]
        }
        set {
            if let newValue = newValue {
                set(newValue, forKey: Keys.sharedGlucoseSparkline.rawValue)
            } else {
                removeObject(forKey: Keys.sharedGlucoseSparkline.rawValue)
            }
        }
    }

    var nightscoutApiSecret: String {
        get {
            return string(forKey: Keys.nightscoutApiSecret.rawValue) ?? ""
        }
        set {
            if newValue.isEmpty {
                removeObject(forKey: Keys.nightscoutApiSecret.rawValue)
            } else {
                set(newValue, forKey: Keys.nightscoutApiSecret.rawValue)
            }
        }
    }

    var nightscoutURL: String {
        get {
            return string(forKey: Keys.nightscoutURL.rawValue) ?? ""
        }
        set {
            if newValue.isEmpty {
                removeObject(forKey: Keys.nightscoutURL.rawValue)
            } else {
                set(newValue, forKey: Keys.nightscoutURL.rawValue)
            }
        }
    }

    var nightscoutUpload: Bool {
        get {
            if object(forKey: Keys.nightscoutUpload.rawValue) != nil {
                return bool(forKey: Keys.nightscoutUpload.rawValue)
            }

            return false
        }
        set {
            set(newValue, forKey: Keys.nightscoutUpload.rawValue)
        }
    }

    var readGlucose: Bool {
        get {
            if object(forKey: Keys.readGlucose.rawValue) != nil {
                return bool(forKey: Keys.readGlucose.rawValue)
            }

            return false
        }
        set {
            set(newValue, forKey: Keys.readGlucose.rawValue)
        }
    }

    var selectedCalendarTarget: String? {
        get {
            return string(forKey: Keys.selectedCalendarTarget.rawValue)
        }
        set {
            if let newValue = newValue {
                set(newValue, forKey: Keys.selectedCalendarTarget.rawValue)
            } else {
                removeObject(forKey: Keys.selectedCalendarTarget.rawValue)
            }
        }
    }

    var selectedConnectionID: String? {
        get {
            return string(forKey: Keys.selectedConnectionID.rawValue)
        }
        set {
            if let newValue = newValue {
                set(newValue, forKey: Keys.selectedConnectionID.rawValue)
            } else {
                removeObject(forKey: Keys.selectedConnectionID.rawValue)
            }
        }
    }

    var sensor: Sensor? {
        get {
            return getObject(forKey: Keys.sensor.rawValue)
        }
        set {
            if let newValue = newValue {
                setObject(newValue, forKey: Keys.sensor.rawValue)
            } else {
                removeObject(forKey: Keys.sensor.rawValue)
            }
        }
    }

    var sensorInterval: Int {
        get {
            if object(forKey: Keys.sensorInterval.rawValue) != nil {
                return integer(forKey: Keys.sensorInterval.rawValue)
            }

            return 1
        }
        set {
            set(newValue, forKey: Keys.sensorInterval.rawValue)
        }
    }

    var showAnnotations: Bool {
        get {
            if object(forKey: Keys.showAnnotations.rawValue) != nil {
                return bool(forKey: Keys.showAnnotations.rawValue)
            }

            return true
        }
        set {
            set(newValue, forKey: Keys.showAnnotations.rawValue)
        }
    }

    var transmitter: Transmitter? {
        get {
            return getObject(forKey: Keys.transmitter.rawValue)
        }
        set {
            if let newValue = newValue {
                setObject(newValue, forKey: Keys.transmitter.rawValue)
            } else {
                removeObject(forKey: Keys.transmitter.rawValue)
            }
        }
    }

    var showSmoothedGlucose: Bool {
        get {
            if object(forKey: Keys.showSmoothedGlucose.rawValue) != nil {
                return bool(forKey: Keys.showSmoothedGlucose.rawValue)
            }

            return false
        }
        set {
            set(newValue, forKey: Keys.showSmoothedGlucose.rawValue)
        }
    }

    var showInsulinInput: Bool {
        get {
            if object(forKey: Keys.showInsulinInput.rawValue) != nil {
                return bool(forKey: Keys.showInsulinInput.rawValue)
            }

            return true
        }
        set {
            set(newValue, forKey: Keys.showInsulinInput.rawValue)
        }
    }

    var showScanlines: Bool {
        get {
            return bool(forKey: Keys.showScanlines.rawValue)
        }
        set {
            set(newValue, forKey: Keys.showScanlines.rawValue)
        }
    }

    var aiConsentFoodPhoto: Bool {
        get {
            return bool(forKey: Keys.aiConsentFoodPhoto.rawValue)
        }
        set {
            set(newValue, forKey: Keys.aiConsentFoodPhoto.rawValue)
        }
    }

    var hasSeenBGRelocationHint: Bool {
        get {
            return bool(forKey: Keys.hasSeenBGRelocationHint.rawValue)
        }
        set {
            set(newValue, forKey: Keys.hasSeenBGRelocationHint.rawValue)
        }
    }

    var appOpenCount: Int {
        get {
            return integer(forKey: Keys.appOpenCount.rawValue)
        }
        set {
            set(newValue, forKey: Keys.appOpenCount.rawValue)
        }
    }

    var appOpenCountFirstRecordedAt: Date? {
        get {
            return object(forKey: Keys.appOpenCountFirstRecordedAt.rawValue) as? Date
        }
        set {
            set(newValue, forKey: Keys.appOpenCountFirstRecordedAt.rawValue)
        }
    }

    var aiConsentDailyDigest: Bool {
        get {
            return bool(forKey: Keys.aiConsentDailyDigest.rawValue)
        }
        set {
            set(newValue, forKey: Keys.aiConsentDailyDigest.rawValue)
        }
    }

    var claudeAPIKeyValid: Bool {
        get {
            return bool(forKey: Keys.claudeAPIKeyValid.rawValue)
        }
        set {
            set(newValue, forKey: Keys.claudeAPIKeyValid.rawValue)
        }
    }

    var thumbCalibrationMM: Double? {
        get {
            let val = double(forKey: Keys.thumbCalibrationMM.rawValue)
            return val > 0 ? val : nil
        }
        set {
            if let newValue = newValue {
                set(newValue, forKey: Keys.thumbCalibrationMM.rawValue)
            } else {
                removeObject(forKey: Keys.thumbCalibrationMM.rawValue)
            }
        }
    }

    var servingPresets: [ServingPreset] {
        get {
            getArray(forKey: Keys.servingPresets.rawValue) ?? ServingPreset.defaults
        }
        set {
            setArray(newValue, forKey: Keys.servingPresets.rawValue)
        }
    }

    var treatmentCycleActive: Bool {
        get {
            if object(forKey: Keys.treatmentCycleActive.rawValue) != nil {
                return bool(forKey: Keys.treatmentCycleActive.rawValue)
            }

            return false
        }
        set {
            set(newValue, forKey: Keys.treatmentCycleActive.rawValue)
        }
    }

    var alarmFiredAt: Date? {
        get {
            let ti = double(forKey: Keys.alarmFiredAt.rawValue)
            return ti > 0 ? Date(timeIntervalSince1970: ti) : nil
        }
        set {
            if let newValue = newValue {
                set(newValue.timeIntervalSince1970, forKey: Keys.alarmFiredAt.rawValue)
            } else {
                removeObject(forKey: Keys.alarmFiredAt.rawValue)
            }
        }
    }

    var treatmentLoggedAt: Date? {
        get {
            let ti = double(forKey: Keys.treatmentLoggedAt.rawValue)
            return ti > 0 ? Date(timeIntervalSince1970: ti) : nil
        }
        set {
            if let newValue = newValue {
                set(newValue.timeIntervalSince1970, forKey: Keys.treatmentLoggedAt.rawValue)
            } else {
                removeObject(forKey: Keys.treatmentLoggedAt.rawValue)
            }
        }
    }

    var treatmentCycleCountdownExpiry: Date? {
        get {
            let ti = double(forKey: Keys.treatmentCycleCountdownExpiry.rawValue)
            return ti > 0 ? Date(timeIntervalSince1970: ti) : nil
        }
        set {
            if let newValue = newValue {
                set(newValue.timeIntervalSince1970, forKey: Keys.treatmentCycleCountdownExpiry.rawValue)
            } else {
                removeObject(forKey: Keys.treatmentCycleCountdownExpiry.rawValue)
            }
        }
    }

    var treatmentCycleSnoozeUntil: Date? {
        get {
            let ti = double(forKey: Keys.treatmentCycleSnoozeUntil.rawValue)
            return ti > 0 ? Date(timeIntervalSince1970: ti) : nil
        }
        set {
            if let newValue = newValue {
                set(newValue.timeIntervalSince1970, forKey: Keys.treatmentCycleSnoozeUntil.rawValue)
            } else {
                removeObject(forKey: Keys.treatmentCycleSnoozeUntil.rawValue)
            }
        }
    }

    var showPredictiveLowAlarm: Bool {
        get {
            if object(forKey: Keys.showPredictiveLowAlarm.rawValue) != nil {
                return bool(forKey: Keys.showPredictiveLowAlarm.rawValue)
            }

            return true
        }
        set {
            set(newValue, forKey: Keys.showPredictiveLowAlarm.rawValue)
        }
    }

    // MARK: Celebrations (DMNC-772)

    var showCelebrations: Bool {
        get {
            if object(forKey: Keys.showCelebrations.rawValue) != nil {
                return bool(forKey: Keys.showCelebrations.rawValue)
            }

            return true
        }
        set {
            set(newValue, forKey: Keys.showCelebrations.rawValue)
        }
    }

    var tightControlStreakCount: Int {
        get {
            integer(forKey: Keys.tightControlStreakCount.rawValue)
        }
        set {
            set(newValue, forKey: Keys.tightControlStreakCount.rawValue)
        }
    }

    // MARK: What's New / changelog (DMNC-1147)

    /// Highest build whose What's New the user has seen. `integer(forKey:)`
    /// returns `0` when unset — the fresh-install sentinel (R6, KTD4).
    var lastSeenBuild: Int {
        get {
            integer(forKey: Keys.lastSeenBuild.rawValue)
        }
        set {
            set(newValue, forKey: Keys.lastSeenBuild.rawValue)
        }
    }

    var tightControlLastCelebratedStreakStart: Date? {
        get {
            let ti = double(forKey: Keys.tightControlLastCelebratedStreakStart.rawValue)
            return ti > 0 ? Date(timeIntervalSince1970: ti) : nil
        }
        set {
            if let newValue = newValue {
                set(newValue.timeIntervalSince1970, forKey: Keys.tightControlLastCelebratedStreakStart.rawValue)
            } else {
                removeObject(forKey: Keys.tightControlLastCelebratedStreakStart.rawValue)
            }
        }
    }

    var tightControlPendingCelebrationCount: Int {
        get {
            integer(forKey: Keys.tightControlPendingCelebrationCount.rawValue)
        }
        set {
            set(newValue, forKey: Keys.tightControlPendingCelebrationCount.rawValue)
        }
    }

    var showHeartRateOverlay: Bool {
        get {
            if object(forKey: Keys.showHeartRateOverlay.rawValue) != nil {
                return bool(forKey: Keys.showHeartRateOverlay.rawValue)
            }
            return false
        }
        set { set(newValue, forKey: Keys.showHeartRateOverlay.rawValue) }
    }

    var markerLanePosition: MarkerLanePosition {
        get { MarkerLanePosition(rawValue: string(forKey: Keys.markerLanePosition.rawValue) ?? "") ?? .top }
        set { set(newValue.rawValue, forKey: Keys.markerLanePosition.rawValue) }
    }

    var hypoTreatmentWaitMinutes: Int {
        get {
            if object(forKey: Keys.hypoTreatmentWaitMinutes.rawValue) != nil {
                return integer(forKey: Keys.hypoTreatmentWaitMinutes.rawValue)
            }

            return 15
        }
        set {
            set(newValue, forKey: Keys.hypoTreatmentWaitMinutes.rawValue)
        }
    }

    var bolusInsulinPreset: InsulinPreset {
        get {
            if let rawValue = string(forKey: Keys.bolusInsulinPreset.rawValue),
               let preset = InsulinPreset(rawValue: rawValue) {
                return preset
            }
            return .rapidActing
        }
        set {
            set(newValue.rawValue, forKey: Keys.bolusInsulinPreset.rawValue)
        }
    }

    var basalDIAMinutes: Int {
        get {
            if object(forKey: Keys.basalDIAMinutes.rawValue) != nil {
                return integer(forKey: Keys.basalDIAMinutes.rawValue)
            }
            return 360
        }
        set {
            set(newValue, forKey: Keys.basalDIAMinutes.rawValue)
        }
    }

    var showSplitIOB: Bool {
        get {
            if object(forKey: Keys.showSplitIOB.rawValue) != nil {
                return bool(forKey: Keys.showSplitIOB.rawValue)
            }
            return false
        }
        set {
            set(newValue, forKey: Keys.showSplitIOB.rawValue)
        }
    }

    // MARK: Day/Night alarm profiles

    var dayAlarmHigh: Int {
        get {
            if object(forKey: Keys.dayAlarmHigh.rawValue) != nil {
                return integer(forKey: Keys.dayAlarmHigh.rawValue)
            }
            return 180
        }
        set {
            set(newValue, forKey: Keys.dayAlarmHigh.rawValue)
        }
    }

    var dayAlarmLow: Int {
        get {
            if object(forKey: Keys.dayAlarmLow.rawValue) != nil {
                return integer(forKey: Keys.dayAlarmLow.rawValue)
            }
            return 80
        }
        set {
            set(newValue, forKey: Keys.dayAlarmLow.rawValue)
        }
    }

    var dayAlarmVolume: Float {
        get {
            if object(forKey: Keys.dayAlarmVolume.rawValue) != nil {
                return float(forKey: Keys.dayAlarmVolume.rawValue)
            }
            return 0.2
        }
        set {
            set(newValue, forKey: Keys.dayAlarmVolume.rawValue)
        }
    }

    var nightAlarmHigh: Int {
        get {
            if object(forKey: Keys.nightAlarmHigh.rawValue) != nil {
                return integer(forKey: Keys.nightAlarmHigh.rawValue)
            }
            return 180
        }
        set {
            set(newValue, forKey: Keys.nightAlarmHigh.rawValue)
        }
    }

    var nightAlarmLow: Int {
        get {
            if object(forKey: Keys.nightAlarmLow.rawValue) != nil {
                return integer(forKey: Keys.nightAlarmLow.rawValue)
            }
            return 80
        }
        set {
            set(newValue, forKey: Keys.nightAlarmLow.rawValue)
        }
    }

    var nightAlarmVolume: Float {
        get {
            if object(forKey: Keys.nightAlarmVolume.rawValue) != nil {
                return float(forKey: Keys.nightAlarmVolume.rawValue)
            }
            return 0.2
        }
        set {
            set(newValue, forKey: Keys.nightAlarmVolume.rawValue)
        }
    }

    var nightStartHour: Int {
        get {
            if object(forKey: Keys.nightStartHour.rawValue) != nil {
                return integer(forKey: Keys.nightStartHour.rawValue)
            }
            return 22
        }
        set {
            set(newValue, forKey: Keys.nightStartHour.rawValue)
        }
    }

    var nightStartMinute: Int {
        get {
            if object(forKey: Keys.nightStartMinute.rawValue) != nil {
                return integer(forKey: Keys.nightStartMinute.rawValue)
            }
            return 0
        }
        set {
            set(newValue, forKey: Keys.nightStartMinute.rawValue)
        }
    }

    var nightEndHour: Int {
        get {
            if object(forKey: Keys.nightEndHour.rawValue) != nil {
                return integer(forKey: Keys.nightEndHour.rawValue)
            }
            return 7
        }
        set {
            set(newValue, forKey: Keys.nightEndHour.rawValue)
        }
    }

    var nightEndMinute: Int {
        get {
            if object(forKey: Keys.nightEndMinute.rawValue) != nil {
                return integer(forKey: Keys.nightEndMinute.rawValue)
            }
            return 0
        }
        set {
            set(newValue, forKey: Keys.nightEndMinute.rawValue)
        }
    }

    // MARK: Daily digest reminder

    /// nil = reminder is off. Both hour AND minute must be present for the
    /// middleware to schedule the notification.
    var dailyDigestReminderHour: Int? {
        get {
            guard object(forKey: Keys.dailyDigestReminderHour.rawValue) != nil else { return nil }
            return integer(forKey: Keys.dailyDigestReminderHour.rawValue)
        }
        set {
            if let newValue = newValue {
                set(newValue, forKey: Keys.dailyDigestReminderHour.rawValue)
            } else {
                removeObject(forKey: Keys.dailyDigestReminderHour.rawValue)
            }
        }
    }

    var dailyDigestReminderMinute: Int? {
        get {
            guard object(forKey: Keys.dailyDigestReminderMinute.rawValue) != nil else { return nil }
            return integer(forKey: Keys.dailyDigestReminderMinute.rawValue)
        }
        set {
            if let newValue = newValue {
                set(newValue, forKey: Keys.dailyDigestReminderMinute.rawValue)
            } else {
                removeObject(forKey: Keys.dailyDigestReminderMinute.rawValue)
            }
        }
    }

    // MARK: Ratio Lab

    /// User's confirmed reference ICR (g/U). nil = no reference set.
    /// Uses `object(forKey:) != nil` guard so a stored 0.0 is still
    /// distinguishable from "never set" (same pattern as dailyDigestReminderHour).
    var confirmedICR: Double? {
        get {
            guard object(forKey: Keys.confirmedICR.rawValue) != nil else { return nil }
            return double(forKey: Keys.confirmedICR.rawValue)
        }
        set {
            if let newValue = newValue {
                set(newValue, forKey: Keys.confirmedICR.rawValue)
            } else {
                removeObject(forKey: Keys.confirmedICR.rawValue)
            }
        }
    }

    // MARK: Migration helpers

    /// True iff the day/night alarm profile migration has already run.
    /// Used by `AppState.init` to decide whether to seed per-profile keys.
    var hasMigratedAlarmProfiles: Bool {
        object(forKey: Keys.dayAlarmHigh.rawValue) != nil
    }

    var hasLegacyAlarmHigh: Bool { object(forKey: Keys.alarmHigh.rawValue) != nil }
    var hasLegacyAlarmLow: Bool { object(forKey: Keys.alarmLow.rawValue) != nil }
    var hasLegacyAlarmVolume: Bool { object(forKey: Keys.alarmVolume.rawValue) != nil }
}

extension UserDefaults {
    static let shared = UserDefaults(suiteName: stringValue(forKey: "APP_GROUP_ID"))!

    func setArray<Element>(_ array: [Element], forKey key: String) where Element: Encodable {
        let data = try? JSONEncoder().encode(array)
        set(data, forKey: key)
    }

    func getArray<Element>(forKey key: String) -> [Element]? where Element: Decodable {
        guard let data = data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode([Element].self, from: data)
    }

    func setObject<Element>(_ obj: Element, forKey key: String) where Element: Encodable {
        let data = try? JSONEncoder().encode(obj)
        set(data, forKey: key)
    }

    func getObject<Element>(forKey key: String) -> Element? where Element: Decodable {
        guard let data = data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode(Element.self, from: data)
    }

    static func stringValue(forKey key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            fatalError("Invalid value or undefined key")
        }

        return value
    }
}
