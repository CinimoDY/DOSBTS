//
//  DirectAction.swift
//  DOSBTS
//

import Foundation
import OSLog
import SwiftUI

enum DirectAction {
    case addBloodGlucose(glucoseValues: [BloodGlucose])
    case addInsulinDelivery(insulinDeliveryValues: [InsulinDelivery])
    case addCalibration(bloodGlucoseValue: Int)
    case addSensorError(errorValues: [SensorError])
    case addSensorGlucose(glucoseValues: [SensorGlucose])
    case addSensorReadings(readings: [SensorReading])
    case bellmanTestAlarm
    case clearBloodGlucoseValues
    case clearCalibrations
    case clearSensorErrorValues
    case clearSensorGlucoseValues
    case connectConnection
    case deleteBloodGlucose(glucose: BloodGlucose)
    case addExerciseEntry(exerciseEntryValues: [ExerciseEntry])
    case addFavoriteFoodValues(favoriteFoodValues: [FavoriteFood])
    case addMealEntry(mealEntryValues: [MealEntry])
    case addTreatmentEvent(treatmentEvent: TreatmentEvent)
    case deleteFavoriteFood(favoriteFood: FavoriteFood)
    case deleteExerciseEntry(exerciseEntry: ExerciseEntry)
    case deleteInsulinDelivery(insulinDelivery: InsulinDelivery)
    case deleteMealEntry(mealEntry: MealEntry)
    case deleteCalibration(calibration: CustomCalibration)
    case deleteLogs
    case deleteSensorError(error: SensorError)
    case deleteSensorGlucose(glucose: SensorGlucose)
    case disconnectConnection
    case exportToUnknown
    case exportToGlooko
    case exportToTidepool
    case loadBloodGlucoseValues
    case loadExerciseEntryValues
    case loadFavoriteFoodValues
    case loadMealEntryValues
    case loadRecentMealEntries
    case logFavoriteFood(favoriteFood: FavoriteFood)
    case loadInsulinDeliveryValues
    case loadSensorErrorValues
    case loadSensorGlucoseValues
    case loadSensorGlucoseStatistics
    case pairConnection
    case registerConnectionInfo(infos: [SensorConnectionInfo])
    case requestAppleCalendarAccess(enabled: Bool)
    case requestAppleHealthAccess(enabled: Bool)
    case requestAppleHealthImportAccess(enabled: Bool)
    case resetSensor
    case resetError
    case selectCalendarTarget(id: String?)
    case selectConnection(id: String, connection: SensorConnectionProtocol)
    case selectConnectionID(id: String)
    case selectView(viewTag: Int)
    case sendLogs
    case sendDatabase
    case sendFile(fileURL: URL)
    case setAppIsBusy(isBusy: Bool)
    case setIgnoreMute(enabled: Bool)
    case setDayAlarmHigh(value: Int)
    case setDayAlarmLow(value: Int)
    case setDayAlarmVolume(value: Float)
    case setNightAlarmHigh(value: Int)
    case setNightAlarmLow(value: Int)
    case setNightAlarmVolume(value: Float)
    case setNightScheduleStart(hour: Int, minute: Int)
    case setNightScheduleEnd(hour: Int, minute: Int)
    case setAlarmSnoozeUntil(untilDate: Date?, autosnooze: Bool = false)
    case setAppleCalendarExport(enabled: Bool)
    case setAppleHealthExport(enabled: Bool)
    case setAppleHealthImport(enabled: Bool)
    case setAppState(appState: ScenePhase)
    case setBellmanConnectionState(connectionState: BellmanConnectionState)
    case setBellmanNotification(enabled: Bool)
    case setBloodGlucoseValues(glucoseValues: [BloodGlucose])
    case setExerciseEntryValues(exerciseEntryValues: [ExerciseEntry])
    case setFavoriteFoodValues(favoriteFoodValues: [FavoriteFood])
    case setHeartRateSeries(heartRateSeries: [(Date, Double)])
    case setHealthImportExcludedSources(excludedSources: [String])
    case setMealEntryValues(mealEntryValues: [MealEntry])
    case setRecentMealEntries(recentMealEntries: [MealEntry])
    case setInsulinDeliveryValues(insulinDeliveryValues: [InsulinDelivery])
    case setMinSelectedDate(minSelectedDate: Date)
    case setSelectedDate(selectedDate: Date?)
    case setChartShowLines(enabled: Bool)
    case setChartZoomLevel(level: Int)
    case setConnectionAlarmSound(sound: NotificationSound)
    case setConnectionError(errorMessage: String, errorTimestamp: Date)
    case setConnectionPaired(isPaired: Bool)
    case setConnectionPeripheralUUID(peripheralUUID: String?)
    case setConnectionState(connectionState: SensorConnectionState)
    case setExpiringAlarmSound(sound: NotificationSound)
    case setNormalGlucoseNotification(enabled: Bool)
    case setAlarmGlucoseNotification(enabled: Bool)
    case setGlucoseLiveActivity(enabled: Bool)
    case setGlucoseUnit(unit: GlucoseUnit)
    case setHighGlucoseAlarmSound(sound: NotificationSound)
    case setLowGlucoseAlarmSound(sound: NotificationSound)
    case setNightscoutSecret(apiSecret: String)
    case setNightscoutUpload(enabled: Bool)
    case setNightscoutURL(url: String)
    case setPreventScreenLock(enabled: Bool)
    case setReadGlucose(enabled: Bool)
    case setSensor(sensor: Sensor, keepDevice: Bool = false)
    case setSensorErrorValues(errorValues: [SensorError])
    case setSensorGlucoseValues(glucoseValues: [SensorGlucose])
    case setSensorInterval(interval: Int)
    case setSensorState(sensorAge: Int, sensorState: SensorState?)
    case setShowAnnotations(showAnnotations: Bool)
    case setGlucoseStatistics(statistics: GlucoseStatistics)
    case setTransmitter(transmitter: Transmitter)
    case setStatisticsDays(days: Int)
    case setShowSmoothedGlucose(enabled: Bool)
    case setShowInsulinInput(enabled: Bool)
    case setShowScanlines(enabled: Bool)
    case startup
    case shutdown

    case analyzeFood(imageData: Data)
    case analyzeFoodBarcode(code: String)
    case analyzeFoodText(query: String, history: [ConversationTurn] = [])
    case deleteClaudeAPIKey
    case setAIConsentFoodPhoto(enabled: Bool)
    case setHasSeenBGRelocationHint(seen: Bool)
    case incrementAppOpenCount
    case setClaudeAPIKeyValid(isValid: Bool)
    case setFoodAnalysisResult(result: NutritionEstimate?)
    case setFoodAnalysisError(error: String)
    case setFoodAnalysisLoading(isLoading: Bool)
    case setThumbCalibration(widthMM: Double?)
    case loadPersonalFoods
    case loadRecentFoodCorrections
    case reorderFavoriteFoods(favoriteFoodValues: [FavoriteFood])
    case saveMealWithCorrections(meal: MealEntry, corrections: [FoodCorrection])
    case setPersonalFoods(personalFoods: [PersonalFood])
    case setServingPresets(servingPresets: [ServingPreset])
    case setRecentFoodCorrections(recentFoodCorrections: [FoodCorrection])
    case updateFavoriteFood(favoriteFood: FavoriteFood)
    case updateInsulinDelivery(insulinDelivery: InsulinDelivery)
    case updateMealEntry(mealEntry: MealEntry)
    case validateClaudeAPIKey

    // MARK: Treatment Cycle
    case showTreatmentPrompt(alarmFiredAt: Date)
    case setShowTreatmentPrompt(show: Bool)
    case logHypoTreatment(favorite: FavoriteFood, alarmFiredAt: Date, overrideTimestamp: Date?)
    case startTreatmentCycle
    case endTreatmentCycle
    case dismissTreatmentCycle
    case treatmentCycleRecovered(glucoseValue: Int)
    case treatmentCycleStillLow(glucoseValue: Int)
    case setHypoTreatmentWaitMinutes(minutes: Int)

    // MARK: Predictive Low Alarm
    case setShowPredictiveLowAlarm(enabled: Bool)
    case setPredictiveLowAlarmFired(fired: Bool)

    // MARK: Celebrations (DMNC-772)
    case setShowCelebrations(enabled: Bool)
    /// A qualifying tight-control streak fired. Increments the lifetime count and stores the
    /// dedup marker (the run's start). `deferred` also bumps the pending ×N toast count.
    case tightControlStreakCelebrated(streakStart: Date, deferred: Bool)
    /// Sets the dedup marker without incrementing the count — used to "consume" the current
    /// in-progress run when Celebrations is re-enabled, so re-enabling can't insta-fire (AE9).
    case setTightControlLastCelebratedStreakStart(start: Date?)
    /// Clears the pending deferred-celebration count after the consolidated toast is presented.
    case clearTightControlPendingCelebrations
    /// Asks ContentView to present a celebration toast (ephemeral; set by the middleware).
    case presentTightControlCelebration(celebration: TightControlCelebration)
    /// Clears the transient celebration after the toast has been shown.
    case clearTightControlCelebration

    // MARK: What's New / changelog (DMNC-1147)
    /// Records the highest build whose What's New the user has seen. Dispatched
    /// at present time (and silently on fresh install) — never on dismiss (KTD5).
    case setLastSeenBuild(build: Int)
    /// Pushes (non-nil) or clears (nil) the deep-link Settings-category target.
    case setSettingsCategory(category: SettingsCategory?)

    // MARK: Heart Rate Overlay (DMNC-848)
    case setShowHeartRateOverlay(enabled: Bool)

    // MARK: Marker Lane Position (DMNC-848 D7)
    case setMarkerLanePosition(position: MarkerLanePosition)

    // MARK: IOB
    case setBolusInsulinPreset(preset: InsulinPreset)
    case setBasalDIAMinutes(minutes: Int)
    case setShowSplitIOB(enabled: Bool)
    case setIOBDeliveries(deliveries: [InsulinDelivery])
    case loadIOBDeliveries

    // MARK: Meal Impact
    case loadScoredMealEntryIds
    case setScoredMealEntryIds(scoredMealEntryIds: Set<UUID>)

    // MARK: Daily Digest
    case loadDailyDigest(date: Date)
    case setDailyDigest(digest: DailyDigest?)
    case setDailyDigestError
    case generateDailyDigestInsight(date: Date, force: Bool = false)
    case setDailyDigestInsight(date: Date, insight: String)
    case setDailyDigestInsightError
    case setDailyDigestEvents(events: DailyDigestEvents)
    case setAIConsentDailyDigest(enabled: Bool)
    case setDailyDigestReminderTime(hour: Int?, minute: Int?)

    // MARK: Ratio Lab
    case loadRatioEvidence
    case setRatioEvidence(evidence: RatioEvidence?)
    case setConfirmedICR(icr: Double?)

    case debugAlarm
    case debugNotification
}

