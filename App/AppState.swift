//
//  UserDefaultsAppState.swift
//  DOSBTS
//

import Combine
import Foundation
import SwiftUI
import UserNotifications

#if canImport(CoreNFC)
    import CoreNFC
#endif

// MARK: - AppState

struct AppState: DirectState {
    // MARK: Lifecycle

    /// - Parameter defaults: backing store for persisted settings. The app
    ///   always uses `.standard`; tests inject a fresh suite per test so
    ///   parallel suites can't pollute each other's keys.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        #if targetEnvironment(simulator)
            let defaultConnectionID = DirectConfig.virtualID
        #else
            #if canImport(CoreNFC)
                let defaultConnectionID = NFCTagReaderSession.readingAvailable
                    ? DirectConfig.libre2ID
                    : DirectConfig.bubbleID
            #else
                let defaultConnectionID = DirectConfig.bubbleID
            #endif
        #endif

        if UserDefaults.shared.glucoseUnit == nil {
            UserDefaults.shared.glucoseUnit = defaults.glucoseUnit ?? .mgdL
        }

        if let sensor = defaults.sensor, UserDefaults.shared.sensor == nil {
            UserDefaults.shared.sensor = sensor
        }

        if let transmitter = defaults.transmitter, UserDefaults.shared.transmitter == nil {
            UserDefaults.shared.transmitter = transmitter
        }

        // Day/Night alarm profile migration. Runs once when per-profile keys are absent.
        // Trigger condition: `hasMigratedAlarmProfiles` (i.e. dayAlarmHigh present) only —
        // sufficient because dual-write keeps the legacy `alarmHigh` key present forever
        // after the first day-side edit, so adding `&& alarmHigh != nil` would always be
        // true and break re-run protection.
        if !defaults.hasMigratedAlarmProfiles {
            // If a legacy install exists, copy its values into both profiles. Otherwise the
            // UserDefaults computed accessors will return their built-in defaults (180/80/0.2)
            // when we read below.
            let legacyHigh = defaults.hasLegacyAlarmHigh ? defaults.alarmHigh : nil
            let legacyLow = defaults.hasLegacyAlarmLow ? defaults.alarmLow : nil
            let legacyVolume = defaults.hasLegacyAlarmVolume ? defaults.alarmVolume : nil

            defaults.dayAlarmHigh = legacyHigh ?? 180
            defaults.nightAlarmHigh = legacyHigh ?? 180
            defaults.dayAlarmLow = legacyLow ?? 80
            defaults.nightAlarmLow = legacyLow ?? 80
            // Match the legacy implicit default (0.2) so users who never customised
            // volume don't experience a 2.5x volume jump after upgrade. Plan promised
            // "observable behavior unchanged"; the migration must preserve that.
            defaults.dayAlarmVolume = legacyVolume ?? 0.2
            defaults.nightAlarmVolume = legacyVolume ?? 0.2
            defaults.nightStartHour = 22
            defaults.nightStartMinute = 0
            defaults.nightEndHour = 7
            defaults.nightEndMinute = 0
        }

        self.dayAlarmHigh = defaults.dayAlarmHigh
        self.dayAlarmLow = defaults.dayAlarmLow
        self.dayAlarmVolume = defaults.dayAlarmVolume
        self.nightAlarmHigh = defaults.nightAlarmHigh
        self.nightAlarmLow = defaults.nightAlarmLow
        self.nightAlarmVolume = defaults.nightAlarmVolume
        self.nightStartHour = defaults.nightStartHour
        self.nightStartMinute = defaults.nightStartMinute
        self.nightEndHour = defaults.nightEndHour
        self.nightEndMinute = defaults.nightEndMinute
        self.appleCalendarExport = defaults.appleCalendarExport
        self.appleHealthExport = defaults.appleHealthExport
        self.appleHealthImport = defaults.appleHealthImport
        self.healthImportExcludedSources = defaults.healthImportExcludedSources
        self.bellmanAlarm = defaults.bellmanAlarm
        self.chartShowLines = defaults.chartShowLines
        self.chartZoomLevel = defaults.chartZoomLevel
        self.connectionAlarmSound = defaults.connectionAlarmSound
        self.connectionPeripheralUUID = defaults.connectionPeripheralUUID
        self.customCalibration = defaults.customCalibration
        self.expiringAlarmSound = defaults.expiringAlarmSound
        self.normalGlucoseNotification = defaults.normalGlucoseNotification
        self.alarmGlucoseNotification = defaults.alarmGlucoseNotification
        self.glucoseLiveActivity = defaults.glucoseLiveActivity
        self.ignoreMute = defaults.ignoreMute
        self.glucoseUnit = UserDefaults.shared.glucoseUnit ?? .mgdL
        self.highGlucoseAlarmSound = defaults.highGlucoseAlarmSound
        self.isConnectionPaired = defaults.isConnectionPaired
        self.latestBloodGlucose = UserDefaults.shared.latestBloodGlucose
        self.latestSensorGlucose = UserDefaults.shared.latestSensorGlucose
        self.latestSensorError = UserDefaults.shared.latestSensorError
        self.latestInsulinDelivery = UserDefaults.shared.latestInsulinDelivery
        self.lowGlucoseAlarmSound = defaults.lowGlucoseAlarmSound
        self.nightscoutApiSecret = defaults.nightscoutApiSecret
        self.nightscoutUpload = defaults.nightscoutUpload
        self.nightscoutURL = defaults.nightscoutURL
        self.readGlucose = defaults.readGlucose
        self.selectedCalendarTarget = defaults.selectedCalendarTarget
        self.selectedConnectionID = defaults.selectedConnectionID ?? defaultConnectionID
        self.sensor = UserDefaults.shared.sensor
        self.sensorInterval = defaults.sensorInterval
        self.showAnnotations = defaults.showAnnotations
        self.transmitter = UserDefaults.shared.transmitter
        self.showSmoothedGlucose = defaults.showSmoothedGlucose
        self.showInsulinInput = defaults.showInsulinInput
        self.showScanlines = defaults.showScanlines
        self.aiConsentFoodPhoto = defaults.aiConsentFoodPhoto
        self.hasSeenBGRelocationHint = defaults.hasSeenBGRelocationHint
        self.appOpenCount = defaults.appOpenCount
        self.appOpenCountFirstRecordedAt = defaults.appOpenCountFirstRecordedAt
        self.aiConsentDailyDigest = defaults.aiConsentDailyDigest
        self.dailyDigestReminderHour = defaults.dailyDigestReminderHour
        self.dailyDigestReminderMinute = defaults.dailyDigestReminderMinute
        self.claudeAPIKeyValid = defaults.claudeAPIKeyValid
        self.thumbCalibrationMM = defaults.thumbCalibrationMM
        // Persist defaults on first launch so UUIDs are stable
        if defaults.data(forKey: "libre-direct.settings.serving-presets") == nil {
            defaults.servingPresets = ServingPreset.defaults
        }
        self.servingPresets = defaults.servingPresets
        self.treatmentCycleActive = defaults.treatmentCycleActive
        self.alarmFiredAt = defaults.alarmFiredAt
        self.treatmentLoggedAt = defaults.treatmentLoggedAt
        self.treatmentCycleCountdownExpiry = defaults.treatmentCycleCountdownExpiry
        self.treatmentCycleSnoozeUntil = defaults.treatmentCycleSnoozeUntil
        self.hypoTreatmentWaitMinutes = defaults.hypoTreatmentWaitMinutes
        self.showPredictiveLowAlarm = defaults.showPredictiveLowAlarm
        self.showMissedBolusNudge = defaults.showMissedBolusNudge
        self.showHeartRateOverlay = defaults.showHeartRateOverlay
        self.markerLanePosition = defaults.markerLanePosition
        self.bolusInsulinPreset = defaults.bolusInsulinPreset
        self.basalDIAMinutes = defaults.basalDIAMinutes
        self.showSplitIOB = defaults.showSplitIOB
        self.showCelebrations = defaults.showCelebrations
        self.tightControlStreakCount = defaults.tightControlStreakCount
        self.tightControlLastCelebratedStreakStart = defaults.tightControlLastCelebratedStreakStart
        self.tightControlPendingCelebrationCount = defaults.tightControlPendingCelebrationCount
        self.lastSeenBuild = defaults.lastSeenBuild
        self.confirmedICR = defaults.confirmedICR
        self.selectedReportType = defaults.selectedReportType
        self.listSectionExpanded = defaults.listSectionExpanded
    }

    // MARK: Internal

    /// Backing store all `didSet` persistence goes through (see init).
    let defaults: UserDefaults

    var appIsBusy = false
    var appState: ScenePhase = .inactive
    var alarmSnoozeUntil: Date? = nil
    var alarmSnoozeKind: Alarm?
    var bellmanConnectionState: BellmanConnectionState = .disconnected
    var bloodGlucoseHistory: [BloodGlucose] = []
    var bloodGlucoseValues: [BloodGlucose] = []
    var exerciseEntryValues: [ExerciseEntry] = []
    var heartRateSeries: [(Date, Double)] = []
    var healthImportExcludedSources: [String] { didSet { defaults.healthImportExcludedSources = healthImportExcludedSources } }
    var insulinDeliveryValues: [InsulinDelivery] = []
    var favoriteFoodValues: [FavoriteFood] = []
    var personalFoodValues: [PersonalFood] = []
    var recentFoodCorrections: [FoodCorrection] = []
    var recentMealEntries: [MealEntry] = []
    var mealEntryValues: [MealEntry] = []
    var connectionError: String?
    var connectionErrorTimestamp: Date?
    var connectionInfos: [SensorConnectionInfo] = []
    var connectionState: SensorConnectionState = .disconnected
    var preventScreenLock = false
    var selectedConnection: SensorConnectionProtocol?
    var selectedConfiguration: [SensorConnectionConfigurationOption] = []
    var minSelectedDate: Date = .init()
    var selectedDate: Date?
    var sensorErrorValues: [SensorError] = []
    var sensorGlucoseHistory: [SensorGlucose] = []
    var sensorGlucoseValues: [SensorGlucose] = []
    var glucoseStatistics: GlucoseStatistics?
    var targetValue = 100
    var selectedView = DirectConfig.overviewViewTag
    var statisticsDays = 3
   
    var appSerial: String {
        UserDefaults.shared.appSerial
    }

    // Day setters dual-write to legacy keys so a rollback to the prior binary
    // recovers to the user's day configuration. Night setters do not dual-write.
    var dayAlarmHigh: Int {
        didSet {
            defaults.dayAlarmHigh = dayAlarmHigh
            defaults.alarmHigh = dayAlarmHigh
        }
    }

    var dayAlarmLow: Int {
        didSet {
            defaults.dayAlarmLow = dayAlarmLow
            defaults.alarmLow = dayAlarmLow
        }
    }

    var dayAlarmVolume: Float {
        didSet {
            defaults.dayAlarmVolume = dayAlarmVolume
            defaults.alarmVolume = dayAlarmVolume
        }
    }

    var nightAlarmHigh: Int { didSet { defaults.nightAlarmHigh = nightAlarmHigh } }
    var nightAlarmLow: Int { didSet { defaults.nightAlarmLow = nightAlarmLow } }
    var nightAlarmVolume: Float { didSet { defaults.nightAlarmVolume = nightAlarmVolume } }
    var nightStartHour: Int { didSet { defaults.nightStartHour = nightStartHour } }
    var nightStartMinute: Int { didSet { defaults.nightStartMinute = nightStartMinute } }
    var nightEndHour: Int { didSet { defaults.nightEndHour = nightEndHour } }
    var nightEndMinute: Int { didSet { defaults.nightEndMinute = nightEndMinute } }
    var appleCalendarExport: Bool { didSet { defaults.appleCalendarExport = appleCalendarExport } }
    var appleHealthExport: Bool { didSet { defaults.appleHealthExport = appleHealthExport } }
    var appleHealthImport: Bool { didSet { defaults.appleHealthImport = appleHealthImport } }
    var bellmanAlarm: Bool { didSet { defaults.bellmanAlarm = bellmanAlarm } }
    var chartShowLines: Bool { didSet { defaults.chartShowLines = chartShowLines } }
    var chartZoomLevel: Int { didSet { defaults.chartZoomLevel = chartZoomLevel } }
    var connectionAlarmSound: NotificationSound { didSet { defaults.connectionAlarmSound = connectionAlarmSound } }
    var connectionPeripheralUUID: String? { didSet { defaults.connectionPeripheralUUID = connectionPeripheralUUID } }
    var customCalibration: [CustomCalibration] { didSet { defaults.customCalibration = customCalibration } }
    var expiringAlarmSound: NotificationSound { didSet { defaults.expiringAlarmSound = expiringAlarmSound } }
    var normalGlucoseNotification: Bool { didSet { defaults.normalGlucoseNotification = normalGlucoseNotification } }
    var alarmGlucoseNotification: Bool { didSet { defaults.alarmGlucoseNotification = alarmGlucoseNotification } }
    var glucoseLiveActivity: Bool { didSet { defaults.glucoseLiveActivity = glucoseLiveActivity } }
    var glucoseUnit: GlucoseUnit { didSet { UserDefaults.shared.glucoseUnit = glucoseUnit } }
    var highGlucoseAlarmSound: NotificationSound { didSet { defaults.highGlucoseAlarmSound = highGlucoseAlarmSound } }
    var ignoreMute: Bool { didSet { defaults.ignoreMute = ignoreMute } }
    var isConnectionPaired: Bool { didSet { defaults.isConnectionPaired = isConnectionPaired } }
    var latestBloodGlucose: BloodGlucose? { didSet { UserDefaults.shared.latestBloodGlucose = latestBloodGlucose } }
    var latestSensorError: SensorError? { didSet { UserDefaults.shared.latestSensorError = latestSensorError } }
    var latestSensorGlucose: SensorGlucose? { didSet { UserDefaults.shared.latestSensorGlucose = latestSensorGlucose } }
    var latestInsulinDelivery: InsulinDelivery? { didSet { UserDefaults.shared.latestInsulinDelivery = latestInsulinDelivery } }
    var lowGlucoseAlarmSound: NotificationSound { didSet { defaults.lowGlucoseAlarmSound = lowGlucoseAlarmSound } }
    var nightscoutApiSecret: String { didSet { defaults.nightscoutApiSecret = nightscoutApiSecret } }
    var nightscoutUpload: Bool { didSet { defaults.nightscoutUpload = nightscoutUpload } }
    var nightscoutURL: String { didSet { defaults.nightscoutURL = nightscoutURL } }
    var readGlucose: Bool { didSet { defaults.readGlucose = readGlucose } }
    var selectedCalendarTarget: String? { didSet { defaults.selectedCalendarTarget = selectedCalendarTarget } }
    var selectedConnectionID: String? { didSet { defaults.selectedConnectionID = selectedConnectionID } }
    var sensor: Sensor? { didSet { UserDefaults.shared.sensor = sensor } }
    var sensorInterval: Int { didSet { defaults.sensorInterval = sensorInterval } }
    var showAnnotations: Bool { didSet { defaults.showAnnotations = showAnnotations } }
    var transmitter: Transmitter? { didSet { UserDefaults.shared.transmitter = transmitter } }
    var showSmoothedGlucose: Bool { didSet { defaults.showSmoothedGlucose = showSmoothedGlucose } }
    var showInsulinInput: Bool { didSet { defaults.showInsulinInput = showInsulinInput } }
    var showScanlines: Bool { didSet { defaults.showScanlines = showScanlines } }
    var aiConsentFoodPhoto: Bool { didSet { defaults.aiConsentFoodPhoto = aiConsentFoodPhoto } }
    var hasSeenBGRelocationHint: Bool { didSet { defaults.hasSeenBGRelocationHint = hasSeenBGRelocationHint } }
    var appOpenCount: Int { didSet { defaults.appOpenCount = appOpenCount } }
    var appOpenCountFirstRecordedAt: Date? { didSet { defaults.appOpenCountFirstRecordedAt = appOpenCountFirstRecordedAt } }
    var claudeAPIKeyValid: Bool { didSet { defaults.claudeAPIKeyValid = claudeAPIKeyValid } }
    var thumbCalibrationMM: Double? { didSet { defaults.thumbCalibrationMM = thumbCalibrationMM } }
    var servingPresets: [ServingPreset] { didSet { defaults.servingPresets = servingPresets } }
    var foodAnalysisResult: NutritionEstimate?
    var foodAnalysisError: String?
    var foodAnalysisLoading = false

    // MARK: Treatment Cycle
    var treatmentCycleActive: Bool { didSet { defaults.treatmentCycleActive = treatmentCycleActive } }
    var showTreatmentPrompt: Bool = false
    var alarmFiredAt: Date? { didSet { defaults.alarmFiredAt = alarmFiredAt } }
    var treatmentLoggedAt: Date? { didSet { defaults.treatmentLoggedAt = treatmentLoggedAt } }
    var treatmentCycleCountdownExpiry: Date? { didSet { defaults.treatmentCycleCountdownExpiry = treatmentCycleCountdownExpiry } }
    var treatmentCycleSnoozeUntil: Date? { didSet { defaults.treatmentCycleSnoozeUntil = treatmentCycleSnoozeUntil } }
    var hypoTreatmentWaitMinutes: Int { didSet { defaults.hypoTreatmentWaitMinutes = hypoTreatmentWaitMinutes } }
    var recheckDispatched: Bool = false

    // MARK: Predictive Low Alarm
    var showPredictiveLowAlarm: Bool { didSet { defaults.showPredictiveLowAlarm = showPredictiveLowAlarm } }
    var predictiveLowAlarmFired: Bool = false

    // MARK: Missed-Bolus Nudge (DMNC-1300)
    var showMissedBolusNudge: Bool { didSet { defaults.showMissedBolusNudge = showMissedBolusNudge } }

    // MARK: Heart Rate Overlay (DMNC-848)
    var showHeartRateOverlay: Bool { didSet { defaults.showHeartRateOverlay = showHeartRateOverlay } }

    // MARK: Marker Lane Position (DMNC-848 D7)
    var markerLanePosition: MarkerLanePosition { didSet { defaults.markerLanePosition = markerLanePosition } }

    // MARK: IOB
    var bolusInsulinPreset: InsulinPreset { didSet { defaults.bolusInsulinPreset = bolusInsulinPreset } }
    var basalDIAMinutes: Int { didSet { defaults.basalDIAMinutes = basalDIAMinutes } }
    var showSplitIOB: Bool { didSet { defaults.showSplitIOB = showSplitIOB } }
    var iobDeliveries: [InsulinDelivery] = []

    // MARK: Meal Impact
    var scoredMealEntryIds: Set<UUID> = []

    // MARK: Daily Digest
    var currentDailyDigest: DailyDigest?
    var dailyDigestLoading: Bool = false
    var dailyDigestInsightLoading: Bool = false
    var dailyDigestEvents: DailyDigestEvents?
    var aiConsentDailyDigest: Bool { didSet { defaults.aiConsentDailyDigest = aiConsentDailyDigest } }
    var dailyDigestReminderHour: Int? { didSet { defaults.dailyDigestReminderHour = dailyDigestReminderHour } }
    var dailyDigestReminderMinute: Int? { didSet { defaults.dailyDigestReminderMinute = dailyDigestReminderMinute } }

    // MARK: Celebrations (DMNC-772)
    var showCelebrations: Bool { didSet { defaults.showCelebrations = showCelebrations } }
    var tightControlStreakCount: Int { didSet { defaults.tightControlStreakCount = tightControlStreakCount } }
    var tightControlLastCelebratedStreakStart: Date? { didSet { defaults.tightControlLastCelebratedStreakStart = tightControlLastCelebratedStreakStart } }
    var tightControlPendingCelebrationCount: Int { didSet { defaults.tightControlPendingCelebrationCount = tightControlPendingCelebrationCount } }
    var tightControlCelebration: TightControlCelebration? // ephemeral — not persisted

    // MARK: What's New / changelog (DMNC-1147)
    var lastSeenBuild: Int { didSet { defaults.lastSeenBuild = lastSeenBuild } }
    var selectedSettingsCategory: SettingsCategory? // ephemeral nav state — not persisted

    // MARK: Ratio Lab
    var ratioEvidence: RatioEvidence? // transient — loaded on demand, not persisted
    var confirmedICR: Double? { didSet { defaults.confirmedICR = confirmedICR } }
    // MARK: View State Persistence (DMNC-1293)
    var selectedReportType: ReportType { didSet { defaults.selectedReportType = selectedReportType } }
    var listSectionExpanded: [String: Bool] { didSet { defaults.listSectionExpanded = listSectionExpanded } }
}
