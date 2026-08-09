//
//  DirectState.swift
//  DOSBTS
//

import Combine
import Foundation
import SwiftUI

// MARK: - DirectState

protocol DirectState {
    var appIsBusy: Bool { get set }
    var appSerial: String { get }
    var appState: ScenePhase { get set }
    var alarmHigh: Int { get }
    var alarmLow: Int { get }
    var alarmSnoozeUntil: Date? { get set }
    var alarmSnoozeKind: Alarm? { get set }
    var alarmVolume: Float { get }
    var dayAlarmHigh: Int { get set }
    var dayAlarmLow: Int { get set }
    var dayAlarmVolume: Float { get set }
    var nightAlarmHigh: Int { get set }
    var nightAlarmLow: Int { get set }
    var nightAlarmVolume: Float { get set }
    var nightStartHour: Int { get set }
    var nightStartMinute: Int { get set }
    var nightEndHour: Int { get set }
    var nightEndMinute: Int { get set }
    var appleCalendarExport: Bool { get set }
    var appleHealthExport: Bool { get set }
    var appleHealthImport: Bool { get set }
    var bellmanAlarm: Bool { get set }
    var bellmanConnectionState: BellmanConnectionState { get set }
    var bloodGlucoseValues: [BloodGlucose] { get set }
    var chartShowLines: Bool { get set }
    var chartZoomLevel: Int { get set }
    var connectionAlarmSound: NotificationSound { get set }
    var connectionError: String? { get set }
    var connectionErrorTimestamp: Date? { get set }
    var connectionInfos: [SensorConnectionInfo] { get set }
    var connectionPeripheralUUID: String? { get set }
    var connectionState: SensorConnectionState { get set }
    var customCalibration: [CustomCalibration] { get set }
    var expiringAlarmSound: NotificationSound { get set }
    var normalGlucoseNotification: Bool { get set }
    var alarmGlucoseNotification: Bool { get set }
    var glucoseLiveActivity: Bool { get set }
    var glucoseUnit: GlucoseUnit { get set }
    var highGlucoseAlarmSound: NotificationSound { get set }
    var ignoreMute: Bool { get set }
    var isConnectionPaired: Bool { get set }
    var exerciseEntryValues: [ExerciseEntry] { get set }
    var heartRateSeries: [(Date, Double)] { get set }
    var healthImportExcludedSources: [String] { get set }
    var insulinDeliveryValues: [InsulinDelivery] { get set }
    var favoriteFoodValues: [FavoriteFood] { get set }
    var recentMealEntries: [MealEntry] { get set }
    var mealEntryValues: [MealEntry] { get set }
    var journalNoteValues: [JournalNote] { get set }
    var latestBloodGlucose: BloodGlucose? { get set }
    var latestInsulinDelivery: InsulinDelivery? { get set }
    var latestSensorGlucose: SensorGlucose? { get set }
    var latestSensorError: SensorError? { get set }
    var lowGlucoseAlarmSound: NotificationSound { get set }
    var nightscoutApiSecret: String { get set }
    var nightscoutUpload: Bool { get set }
    var nightscoutURL: String { get set }
    var preventScreenLock: Bool { get set }
    var readGlucose: Bool { get set }
    var selectedCalendarTarget: String? { get set }
    var selectedConnection: SensorConnectionProtocol? { get set }
    var selectedConnectionID: String? { get set }
    var selectedConfiguration: [SensorConnectionConfigurationOption] { get set }
    var selectedView: Int { get set }
    var minSelectedDate: Date { get set }
    var selectedDate: Date? { get set }
    var sensor: Sensor? { get set }
    var sensorErrorValues: [SensorError] { get set }
    var sensorGlucoseValues: [SensorGlucose] { get set }
    var sensorInterval: Int { get set }
    var showAnnotations: Bool { get set }
    var statisticsDays: Int { get set }
    var glucoseStatistics: GlucoseStatistics? { get set }
    var targetValue: Int { get set }
    var transmitter: Transmitter? { get set }
    var showSmoothedGlucose: Bool { get set }
    var showInsulinInput: Bool { get set }
    var showScanlines: Bool { get set }
    var aiConsentFoodPhoto: Bool { get set }
    var hasSeenBGRelocationHint: Bool { get set }
    var appOpenCount: Int { get set }
    var appOpenCountFirstRecordedAt: Date? { get set }
    var claudeAPIKeyValid: Bool { get set }
    var foodAnalysisResult: NutritionEstimate? { get set }
    var foodAnalysisError: String? { get set }
    var foodAnalysisLoading: Bool { get set }
    var personalFoodValues: [PersonalFood] { get set }
    var recentFoodCorrections: [FoodCorrection] { get set }
    var servingPresets: [ServingPreset] { get set }
    var thumbCalibrationMM: Double? { get set }

    // MARK: Treatment Cycle
    var treatmentCycleActive: Bool { get set }
    var showTreatmentPrompt: Bool { get set }
    var alarmFiredAt: Date? { get set }
    var treatmentLoggedAt: Date? { get set }
    var treatmentCycleCountdownExpiry: Date? { get set }
    var treatmentCycleSnoozeUntil: Date? { get set }
    var hypoTreatmentWaitMinutes: Int { get set }
    var recheckDispatched: Bool { get set }

    // MARK: Predictive Low Alarm
    var showPredictiveLowAlarm: Bool { get set }
    var predictiveLowAlarmFired: Bool { get set }

    // MARK: Missed-Bolus Nudge (DMNC-1300)
    var showMissedBolusNudge: Bool { get set }

    // MARK: Heart Rate Overlay (DMNC-848)
    var showHeartRateOverlay: Bool { get set }

    // MARK: Marker Lane Position (DMNC-848 D7)
    var markerLanePosition: MarkerLanePosition { get set }

    // MARK: IOB
    var bolusInsulinPreset: InsulinPreset { get set }
    var basalDIAMinutes: Int { get set }
    var showSplitIOB: Bool { get set }
    var iobDeliveries: [InsulinDelivery] { get set }

    // MARK: Meal Impact
    var scoredMealEntryIds: Set<UUID> { get set }
    var scoredPersonalFoodValues: [PersonalFood] { get set }

    // MARK: Ratio Lab
    /// Transient — loaded on demand when Ratio Lab screen opens. Not persisted.
    var ratioEvidence: RatioEvidence? { get set }
    /// Persisted confirmed ICR (g/U) chosen by the user as their reference. nil = not set.
    var confirmedICR: Double? { get set }

    // MARK: Daily Digest
    var currentDailyDigest: DailyDigest? { get set }
    var dailyDigestLoading: Bool { get set }
    var dailyDigestInsightLoading: Bool { get set }
    var dailyDigestEvents: DailyDigestEvents? { get set }
    /// Daily-digest reminder time. nil hour OR nil minute = reminder is off.
    /// Two stored ints rather than a Date so the value is locale-independent
    /// and survives time-zone changes cleanly (same shape the night-window
    /// schedule uses — see `nightStartHour`).
    var dailyDigestReminderHour: Int? { get set }
    var dailyDigestReminderMinute: Int? { get set }
    /// Versioned (DMNC-1485): journal-note text made the V1 consent copy
    /// inaccurate, so the key was bumped rather than silently widened. The
    /// legacy `libre-direct.settings.ai-consent-daily-digest` default is left
    /// in place, unread, for rollback.
    var aiConsentDailyDigestV2: Bool { get set }

    // MARK: Celebrations (DMNC-772)
    var showCelebrations: Bool { get set }
    var tightControlStreakCount: Int { get set }
    var tightControlLastCelebratedStreakStart: Date? { get set }
    var tightControlPendingCelebrationCount: Int { get set }
    /// Ephemeral (not persisted): set by the middleware when a celebration should be
    /// presented, observed by ContentView to drive the toast, then cleared.
    var tightControlCelebration: TightControlCelebration? { get set }

    // MARK: View State Persistence (DMNC-1293)
    /// Chart report type tab (GLUCOSE / TIME IN RANGE / STATISTICS). Persisted
    /// so kill + relaunch restores the last-viewed chart mode.
    var selectedReportType: ReportType { get set }
    /// Per-section expanded state for the Lists tab. Keys are the stable
    /// `sectionName` strings passed to `CollapsableSection`; `true` = expanded.
    /// Defaults to collapsed for any key not present.
    var listSectionExpanded: [String: Bool] { get set }

    // MARK: What's New / changelog (DMNC-1147)
    /// Highest build whose "What's New" the user has seen. `0` is the
    /// fresh-install sentinel (`integer(forKey:)` default) → record current,
    /// present nothing (R6). Advanced at present time, not on dismiss (KTD5).
    var lastSeenBuild: Int { get set }

    /// Transient Settings-category push target for a deep-link tap (KTD6).
    /// NOT persisted — must not survive relaunch, or the app would re-push the
    /// last deep-linked category on cold launch. Cleared on back-navigation.
    var selectedSettingsCategory: SettingsCategory? { get set }
}

extension DirectState {
    // MARK: Day/Night alarm profile

    var activeAlarmProfile: AlarmProfile {
        resolveActiveAlarmProfile(
            at: Date(),
            nightStartHour: nightStartHour,
            nightStartMinute: nightStartMinute,
            nightEndHour: nightEndHour,
            nightEndMinute: nightEndMinute
        )
    }

    var alarmHigh: Int {
        activeAlarmProfile == .night ? nightAlarmHigh : dayAlarmHigh
    }

    var alarmLow: Int {
        activeAlarmProfile == .night ? nightAlarmLow : dayAlarmLow
    }

    var alarmVolume: Float {
        activeAlarmProfile == .night ? nightAlarmVolume : dayAlarmVolume
    }

    var hasConnectionAlarm: Bool {
        connectionAlarmSound != .none
    }

    var hasExpiringAlarm: Bool {
        expiringAlarmSound != .none
    }

    var hasHighGlucoseAlarm: Bool {
        highGlucoseAlarmSound != .none
    }

    var hasLowGlucoseAlarm: Bool {
        lowGlucoseAlarmSound != .none
    }

    var isConnectable: Bool {
        if transmitter != nil, connectableStates.contains(connectionState) {
            return true
        }

        if let sensor = sensor {
            return sensorConnectableStates.contains(sensor.state) && connectableStates.contains(connectionState)
        }

        return false
    }

    var hasSelectedConnection: Bool {
        selectedConnection != nil
    }

    var isDisconnectable: Bool {
        disconnectableStates.contains(connectionState)
    }

    var isSensor: Bool {
        selectedConnection is IsSensor
    }

    var isTransmitter: Bool {
        selectedConnection is IsTransmitter
    }

    var isPairable: Bool {
        !isConnectionPaired && !(connectionState != .disconnected && connectionState != .pairing && connectionState != .scanning && connectionState != .connecting)
    }

    var connectionIsBusy: Bool {
        !(connectionState != .pairing && connectionState != .scanning && connectionState != .connecting)
    }

    var isReady: Bool {
        sensor != nil && sensor!.state == .ready
    }

    var smoothThreshold: Date {
        Date().addingTimeInterval(-DirectConfig.smoothThresholdSeconds)
    }

    func isAlarm(glucoseValue: Int) -> Alarm {
        if glucoseValue < alarmLow {
            return .lowAlarm

        } else if glucoseValue > alarmHigh {
            return .highAlarm
        }

        return .none
    }

    func isSnoozed(alarm: Alarm) -> Bool {
        if let snoozeUntil = alarmSnoozeUntil, Date() < snoozeUntil, alarmSnoozeKind == nil || alarmSnoozeKind == alarm {
            return true
        }

        return false
    }
}

// MARK: - private

private var sensorConnectableStates: Set<SensorState> = [.starting, .ready]
private var connectableStates: Set<SensorConnectionState> = [.disconnected]
private var disconnectableStates: Set<SensorConnectionState> = [.connected, .connecting, .scanning]
