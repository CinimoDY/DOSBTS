//
//  DirectReducerTests.swift
//  DOSBTSTests
//

import Foundation
import Testing
@testable import DOSBTSApp

// MARK: - Reducer Test Helpers

/// Fresh, isolated UserDefaults suite — one per call, never shared between
/// tests, so parallel suites can't pollute each other's keys and nothing
/// persists across runs. Shared by all test files in this target.
func makeTestDefaults() -> UserDefaults {
    let name = "dosbts-tests-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: name) else {
        fatalError("Could not create test UserDefaults suite \(name)")
    }
    defaults.removePersistentDomain(forName: name)
    return defaults
}

/// Creates a minimal AppState for testing. AppState.init() reads from the
/// injected isolated UserDefaults, so these tests exercise the real init path.
/// State mutations are verified by calling directReducer() directly — it's a
/// pure function.
private func makeState() -> AppState {
    AppState(defaults: makeTestDefaults())
}

private func reduce(_ state: inout DirectState, _ action: DirectAction) {
    directReducer(state: &state, action: action)
}

// MARK: - Treatment Cycle Tests

@Suite("Treatment Cycle State")
struct TreatmentCycleTests {

    @Test("startTreatmentCycle sets active state and countdown expiry")
    func startCycle() {
        var state: DirectState = makeState()
        reduce(&state, .startTreatmentCycle)

        #expect(state.treatmentCycleActive == true)
        #expect(state.treatmentCycleCountdownExpiry != nil)
        #expect(state.treatmentCycleSnoozeUntil != nil)
        #expect(state.recheckDispatched == false)
    }

    @Test("dismissTreatmentCycle clears all cycle state")
    func dismissCycle() {
        var state: DirectState = makeState()
        reduce(&state, .startTreatmentCycle)
        reduce(&state, .dismissTreatmentCycle)

        #expect(state.treatmentCycleActive == false)
        #expect(state.alarmFiredAt == nil)
        #expect(state.treatmentLoggedAt == nil)
        #expect(state.treatmentCycleCountdownExpiry == nil)
        #expect(state.treatmentCycleSnoozeUntil == nil)
        #expect(state.recheckDispatched == false)
        #expect(state.showTreatmentPrompt == false)
    }

    @Test("endTreatmentCycle clears cycle state same as dismiss")
    func endCycle() {
        var state: DirectState = makeState()
        reduce(&state, .startTreatmentCycle)
        reduce(&state, .endTreatmentCycle)

        #expect(state.treatmentCycleActive == false)
        #expect(state.treatmentCycleCountdownExpiry == nil)
    }

    @Test("treatmentCycleRecovered sets recheckDispatched")
    func recovered() {
        var state: DirectState = makeState()
        reduce(&state, .startTreatmentCycle)
        reduce(&state, .treatmentCycleRecovered(glucoseValue: 90))

        #expect(state.recheckDispatched == true)
    }

    @Test("treatmentCycleStillLow sets recheckDispatched and showTreatmentPrompt")
    func stillLow() {
        var state: DirectState = makeState()
        reduce(&state, .startTreatmentCycle)
        reduce(&state, .treatmentCycleStillLow(glucoseValue: 55))

        #expect(state.recheckDispatched == true)
        #expect(state.showTreatmentPrompt == true)
    }

    @Test("startTreatmentCycle resets recheckDispatched for chained cycles")
    func chainedCycleResetsRecheck() {
        var state: DirectState = makeState()
        reduce(&state, .startTreatmentCycle)
        reduce(&state, .treatmentCycleStillLow(glucoseValue: 55))
        #expect(state.recheckDispatched == true)

        // Chained cycle: logHypoTreatment resets, then startTreatmentCycle also resets
        reduce(&state, .startTreatmentCycle)
        #expect(state.recheckDispatched == false)
    }

    @Test("logHypoTreatment clears stale countdown expiry to prevent race")
    func logTreatmentClearsExpiry() {
        var state: DirectState = makeState()
        reduce(&state, .startTreatmentCycle)
        // Simulate chained treatment: logHypoTreatment should clear expiry
        let fakeFavorite = FavoriteFood(
            mealDescription: "Test",
            carbsGrams: 15,
            proteinGrams: nil,
            fatGrams: nil,
            calories: nil,
            fiberGrams: nil,
            sortOrder: 0,
            isHypoTreatment: true
        )
        reduce(&state, .logHypoTreatment(favorite: fakeFavorite, alarmFiredAt: Date(), overrideTimestamp: nil))

        #expect(state.treatmentCycleCountdownExpiry == nil) // Cleared to prevent race
        #expect(state.recheckDispatched == false)
        #expect(state.showTreatmentPrompt == false)
    }
}

// MARK: - Predictive Low Alarm Tests

@Suite("Predictive Low Alarm State")
struct PredictiveLowAlarmTests {

    @Test("setShowPredictiveLowAlarm toggles the setting")
    func toggleSetting() {
        var state: DirectState = makeState()
        reduce(&state, .setShowPredictiveLowAlarm(enabled: false))
        #expect(state.showPredictiveLowAlarm == false)

        reduce(&state, .setShowPredictiveLowAlarm(enabled: true))
        #expect(state.showPredictiveLowAlarm == true)
    }

    @Test("setPredictiveLowAlarmFired controls the flag")
    func firedFlag() {
        var state: DirectState = makeState()
        #expect(state.predictiveLowAlarmFired == false)

        reduce(&state, .setPredictiveLowAlarmFired(fired: true))
        #expect(state.predictiveLowAlarmFired == true)

        reduce(&state, .setPredictiveLowAlarmFired(fired: false))
        #expect(state.predictiveLowAlarmFired == false)
    }
}

// MARK: - Alarm Snooze Tests

@Suite("Alarm Snooze State")
struct AlarmSnoozeTests {

    @Test("setAlarmSnoozeUntil sets snooze date")
    func setSnooze() {
        var state: DirectState = makeState()
        let future = Date().addingTimeInterval(5 * 60)
        reduce(&state, .setAlarmSnoozeUntil(untilDate: future, autosnooze: true))

        #expect(state.alarmSnoozeUntil != nil)
    }

    @Test("expired snooze is auto-cleared on next action")
    func expiredSnoozeClearsAutomatically() {
        var state: DirectState = makeState()
        let past = Date().addingTimeInterval(-60) // 1 minute ago
        reduce(&state, .setAlarmSnoozeUntil(untilDate: past, autosnooze: false))

        // Any subsequent action should trigger the auto-clear at the end of the reducer
        reduce(&state, .setShowPredictiveLowAlarm(enabled: true))

        #expect(state.alarmSnoozeUntil == nil)
        #expect(state.alarmSnoozeKind == nil)
    }
}

// MARK: - Show Treatment Prompt Tests

@Suite("Treatment Prompt State")
struct TreatmentPromptTests {

    @Test("showTreatmentPrompt sets flag and alarmFiredAt")
    func showPrompt() {
        var state: DirectState = makeState()
        let now = Date()
        reduce(&state, .showTreatmentPrompt(alarmFiredAt: now))

        #expect(state.showTreatmentPrompt == true)
        #expect(state.alarmFiredAt != nil)
    }

    @Test("setShowTreatmentPrompt clears the flag")
    func clearPrompt() {
        var state: DirectState = makeState()
        reduce(&state, .showTreatmentPrompt(alarmFiredAt: Date()))
        reduce(&state, .setShowTreatmentPrompt(show: false))

        #expect(state.showTreatmentPrompt == false)
    }
}

// MARK: - IOB State Tests

@Suite("IOB State")
struct IOBStateTests {

    @Test("setBolusInsulinPreset updates preset")
    func setPreset() {
        var state: DirectState = makeState()
        reduce(&state, .setBolusInsulinPreset(preset: .ultraRapid))
        #expect(state.bolusInsulinPreset == .ultraRapid)
    }

    @Test("setBasalDIAMinutes updates basalDIAMinutes")
    func setBasalDIA() {
        var state: DirectState = makeState()
        reduce(&state, .setBasalDIAMinutes(minutes: 240))
        #expect(state.basalDIAMinutes == 240)
    }

    @Test("setShowSplitIOB toggles flag")
    func setSplitIOB() {
        var state: DirectState = makeState()
        reduce(&state, .setShowSplitIOB(enabled: true))
        #expect(state.showSplitIOB == true)
    }

    @Test("setIOBDeliveries populates array")
    func setDeliveries() {
        var state: DirectState = makeState()
        let delivery = InsulinDelivery(id: UUID(), starts: Date(), ends: Date(), units: 1.0, type: .correctionBolus)
        reduce(&state, .setIOBDeliveries(deliveries: [delivery]))
        #expect(state.iobDeliveries.count == 1)
    }

    @Test("setIOBDeliveries with empty array clears list")
    func clearDeliveries() {
        var state: DirectState = makeState()
        let delivery = InsulinDelivery(id: UUID(), starts: Date(), ends: Date(), units: 1.0, type: .mealBolus)
        reduce(&state, .setIOBDeliveries(deliveries: [delivery]))
        reduce(&state, .setIOBDeliveries(deliveries: []))
        #expect(state.iobDeliveries.isEmpty)
    }

    @Test("default state has rapidActing preset and 360 basalDIAMinutes")
    func defaultState() {
        let state: DirectState = makeState()
        #expect(state.bolusInsulinPreset == .rapidActing)
        #expect(state.basalDIAMinutes == 360)
        #expect(state.showSplitIOB == false)
    }
}

// MARK: - Alarm Snooze Extended Tests

@Suite("Alarm Snooze — extended")
struct AlarmSnoozeExtendedTests {

    @Test("setAlarmSnoozeUntil with nil clears snooze and kind")
    func clearSnooze() {
        var state: DirectState = makeState()
        let future = Date().addingTimeInterval(5 * 60)
        reduce(&state, .setAlarmSnoozeUntil(untilDate: future, autosnooze: true))
        #expect(state.alarmSnoozeUntil != nil)

        reduce(&state, .setAlarmSnoozeUntil(untilDate: nil, autosnooze: false))
        #expect(state.alarmSnoozeUntil == nil)
        #expect(state.alarmSnoozeKind == nil)
    }
}

// MARK: - Connection State Tests

@Suite("Connection State")
struct ConnectionStateTests {

    @Test("setConnectionState with resetable state clears error")
    func resetableStateClearsError() {
        var state: DirectState = makeState()
        reduce(&state, .setConnectionError(errorMessage: "test error", errorTimestamp: Date()))
        #expect(state.connectionError != nil)

        // .connected is in resetableStates
        reduce(&state, .setConnectionState(connectionState: .connected))
        #expect(state.connectionError == nil)
        #expect(state.connectionErrorTimestamp == nil)
    }

    @Test("setConnectionState with non-resetable state preserves error")
    func nonResetablePreservesError() {
        var state: DirectState = makeState()
        reduce(&state, .setConnectionError(errorMessage: "test error", errorTimestamp: Date()))

        // .connecting is NOT in resetableStates
        reduce(&state, .setConnectionState(connectionState: .connecting))
        #expect(state.connectionError == "test error")
    }

    @Test("setConnectionError sets both message and timestamp")
    func setConnectionError() {
        var state: DirectState = makeState()
        let ts = Date()
        reduce(&state, .setConnectionError(errorMessage: "BLE fail", errorTimestamp: ts))

        #expect(state.connectionError == "BLE fail")
        #expect(state.connectionErrorTimestamp == ts)
    }
}

// MARK: - Alarm Threshold Tests

@Suite("Alarm Thresholds")
struct AlarmThresholdTests {

    @Test("setDayAlarmHigh updates day upper limit only")
    func setHigh() {
        var state: DirectState = makeState()
        let originalNight = state.nightAlarmHigh
        reduce(&state, .setDayAlarmHigh(value: 200))
        #expect(state.dayAlarmHigh == 200)
        #expect(state.nightAlarmHigh == originalNight)
    }

    @Test("setDayAlarmLow updates day lower limit only")
    func setLow() {
        var state: DirectState = makeState()
        let originalNight = state.nightAlarmLow
        reduce(&state, .setDayAlarmLow(value: 60))
        #expect(state.dayAlarmLow == 60)
        #expect(state.nightAlarmLow == originalNight)
    }

    @Test("setNightAlarmHigh updates night upper limit only")
    func setNightHigh() {
        var state: DirectState = makeState()
        let originalDay = state.dayAlarmHigh
        reduce(&state, .setNightAlarmHigh(value: 220))
        #expect(state.nightAlarmHigh == 220)
        #expect(state.dayAlarmHigh == originalDay)
    }

    @Test("setNightAlarmLow updates night lower limit only")
    func setNightLow() {
        var state: DirectState = makeState()
        let originalDay = state.dayAlarmLow
        reduce(&state, .setNightAlarmLow(value: 75))
        #expect(state.nightAlarmLow == 75)
        #expect(state.dayAlarmLow == originalDay)
    }

    @Test("setNightScheduleStart mutates both hour and minute atomically")
    func setNightScheduleStart() {
        var state: DirectState = makeState()
        reduce(&state, .setNightScheduleStart(hour: 23, minute: 30))
        #expect(state.nightStartHour == 23)
        #expect(state.nightStartMinute == 30)
    }

    @Test("setNightScheduleEnd mutates both hour and minute atomically")
    func setNightScheduleEnd() {
        var state: DirectState = makeState()
        reduce(&state, .setNightScheduleEnd(hour: 6, minute: 45))
        #expect(state.nightEndHour == 6)
        #expect(state.nightEndMinute == 45)
    }

    @Test("isAlarm returns lowAlarm when below alarmLow")
    func isAlarmLow() {
        var state: DirectState = makeState()
        reduce(&state, .setDayAlarmLow(value: 70))
        reduce(&state, .setNightAlarmLow(value: 70))
        #expect(state.isAlarm(glucoseValue: 65) == .lowAlarm)
    }

    @Test("isAlarm returns highAlarm when above alarmHigh")
    func isAlarmHigh() {
        var state: DirectState = makeState()
        reduce(&state, .setDayAlarmHigh(value: 180))
        reduce(&state, .setNightAlarmHigh(value: 180))
        #expect(state.isAlarm(glucoseValue: 200) == .highAlarm)
    }

    @Test("isAlarm returns none when in range")
    func isAlarmNone() {
        var state: DirectState = makeState()
        reduce(&state, .setDayAlarmLow(value: 70))
        reduce(&state, .setDayAlarmHigh(value: 180))
        reduce(&state, .setNightAlarmLow(value: 70))
        reduce(&state, .setNightAlarmHigh(value: 180))
        #expect(state.isAlarm(glucoseValue: 120) == .none)
    }
}

// MARK: - Glucose Unit Tests

@Suite("Glucose Unit State")
struct GlucoseUnitTests {

    @Test("setGlucoseUnit switches unit")
    func switchUnit() {
        var state: DirectState = makeState()
        reduce(&state, .setGlucoseUnit(unit: .mmolL))
        #expect(state.glucoseUnit == .mmolL)

        reduce(&state, .setGlucoseUnit(unit: .mgdL))
        #expect(state.glucoseUnit == .mgdL)
    }
}

// MARK: - Sensor Reset Tests

@Suite("Sensor Reset")
struct SensorResetTests {

    @Test("resetSensor clears sensor, calibrations, and errors")
    func resetSensor() {
        var state: DirectState = makeState()
        let sensor = Sensor(
            family: .libre2,
            type: .libre2EU,
            region: .european,
            serial: "TEST",
            state: .ready,
            age: 100,
            lifetime: 20160
        )
        reduce(&state, .setSensor(sensor: sensor, keepDevice: false))
        reduce(&state, .setConnectionError(errorMessage: "err", errorTimestamp: Date()))

        reduce(&state, .resetSensor)
        #expect(state.sensor == nil)
        #expect(state.customCalibration.isEmpty)
        #expect(state.connectionError == nil)
    }
}

// MARK: - Daily Digest Tests

@Suite("Daily Digest State")
struct DailyDigestStateTests {

    @Test("setDailyDigest populates currentDailyDigest")
    func setDigest() {
        var state: DirectState = makeState()
        let digest = DailyDigest(
            date: Date(), tir: 78.0, tbr: 5.0, tar: 17.0,
            avg: 142.0, stdev: 35.0, readings: 288,
            lowCount: 2, highCount: 3,
            totalCarbsGrams: 185.0, totalInsulinUnits: 24.0,
            totalExerciseMinutes: 30.0, mealCount: 3, insulinCount: 5
        )
        reduce(&state, .setDailyDigest(digest: digest))
        #expect(state.currentDailyDigest != nil)
        #expect(state.currentDailyDigest?.tir == 78.0)
        #expect(state.dailyDigestLoading == false)
    }

    @Test("setDailyDigest with nil clears digest")
    func clearDigest() {
        var state: DirectState = makeState()
        let digest = DailyDigest(
            date: Date(), tir: 78.0, tbr: 5.0, tar: 17.0,
            avg: 142.0, stdev: 35.0, readings: 288,
            lowCount: 0, highCount: 0,
            totalCarbsGrams: 0, totalInsulinUnits: 0,
            totalExerciseMinutes: 0, mealCount: 0, insulinCount: 0
        )
        reduce(&state, .setDailyDigest(digest: digest))
        reduce(&state, .setDailyDigest(digest: nil))
        #expect(state.currentDailyDigest == nil)
    }

    @Test("loadDailyDigest sets loading flag")
    func loadSetsLoading() {
        var state: DirectState = makeState()
        reduce(&state, .loadDailyDigest(date: Date()))
        #expect(state.dailyDigestLoading == true)
    }

    @Test("setDailyDigestError clears loading flag")
    func errorClearsLoading() {
        var state: DirectState = makeState()
        reduce(&state, .loadDailyDigest(date: Date()))
        #expect(state.dailyDigestLoading == true)
        reduce(&state, .setDailyDigestError)
        #expect(state.dailyDigestLoading == false)
    }

    @Test("generateDailyDigestInsight sets insight loading")
    func generateSetsInsightLoading() {
        var state: DirectState = makeState()
        reduce(&state, .generateDailyDigestInsight(date: Date()))
        #expect(state.dailyDigestInsightLoading == true)
    }

    @Test("setDailyDigestInsight updates insight on existing digest")
    func setInsight() {
        var state: DirectState = makeState()
        let digest = DailyDigest(
            date: Date(), tir: 78.0, tbr: 5.0, tar: 17.0,
            avg: 142.0, stdev: 35.0, readings: 288,
            lowCount: 0, highCount: 0,
            totalCarbsGrams: 0, totalInsulinUnits: 0,
            totalExerciseMinutes: 0, mealCount: 0, insulinCount: 0
        )
        reduce(&state, .setDailyDigest(digest: digest))
        reduce(&state, .setDailyDigestInsight(date: Date(), insight: "Great day!"))

        #expect(state.currentDailyDigest?.aiInsight == "Great day!")
        #expect(state.currentDailyDigest?.generatedAt != nil)
        #expect(state.dailyDigestInsightLoading == false)
    }

    @Test("setAIConsentDailyDigest toggles consent")
    func toggleConsent() {
        var state: DirectState = makeState()
        reduce(&state, .setAIConsentDailyDigest(enabled: true))
        #expect(state.aiConsentDailyDigest == true)

        reduce(&state, .setAIConsentDailyDigest(enabled: false))
        #expect(state.aiConsentDailyDigest == false)
    }
}

// MARK: - Update Action Reducer Tests

@Suite("Update + Delete Actions — optimistic state (DMNC-905)")
struct UpdateActionReducerTests {

    @Test("updateMealEntry replaces the matching entry by id")
    func updateMealEntryReplacesById() {
        var state: DirectState = makeState()
        let original = MealEntry(timestamp: Date(), mealDescription: "Old", carbsGrams: 30, analysisSessionId: nil)
        state.mealEntryValues = [original]
        let updated = MealEntry(id: original.id, timestamp: original.timestamp, mealDescription: "New", carbsGrams: 45, analysisSessionId: nil)
        reduce(&state, .updateMealEntry(mealEntry: updated))
        #expect(state.mealEntryValues.count == 1)
        #expect(state.mealEntryValues.first?.id == original.id)
        #expect(state.mealEntryValues.first?.mealDescription == "New")
        #expect(state.mealEntryValues.first?.carbsGrams == 45)
    }

    @Test("updateMealEntry appends when no entry with matching id exists (resilience)")
    func updateMealEntryAppendsIfMissing() {
        var state: DirectState = makeState()
        let existing = MealEntry(timestamp: Date(), mealDescription: "Other", carbsGrams: 20, analysisSessionId: nil)
        state.mealEntryValues = [existing]
        let novel = MealEntry(timestamp: Date(), mealDescription: "Novel", carbsGrams: 50, analysisSessionId: nil)
        reduce(&state, .updateMealEntry(mealEntry: novel))
        #expect(state.mealEntryValues.count == 2)
        #expect(state.mealEntryValues.contains(where: { $0.id == novel.id }))
    }

    @Test("updateInsulinDelivery replaces the matching entry by id")
    func updateInsulinDeliveryReplacesById() {
        var state: DirectState = makeState()
        let original = InsulinDelivery(starts: Date(), ends: Date(), units: 4.5, type: .mealBolus)
        state.insulinDeliveryValues = [original]
        let updated = InsulinDelivery(id: original.id, starts: original.starts, ends: original.ends, units: 5.0, type: original.type)
        reduce(&state, .updateInsulinDelivery(insulinDelivery: updated))
        #expect(state.insulinDeliveryValues.count == 1)
        #expect(state.insulinDeliveryValues.first?.id == original.id)
        #expect(state.insulinDeliveryValues.first?.units == 5.0)
    }

    @Test("deleteMealEntry removes the matching entry by id")
    func deleteMealEntryRemovesById() {
        var state: DirectState = makeState()
        let keep = MealEntry(timestamp: Date(), mealDescription: "Keep", carbsGrams: 20, analysisSessionId: nil)
        let toDelete = MealEntry(timestamp: Date(), mealDescription: "Delete me", carbsGrams: 50, analysisSessionId: nil)
        state.mealEntryValues = [keep, toDelete]
        reduce(&state, .deleteMealEntry(mealEntry: toDelete))
        #expect(state.mealEntryValues.count == 1)
        #expect(state.mealEntryValues.first?.id == keep.id)
    }

    @Test("deleteInsulinDelivery removes the matching entry by id")
    func deleteInsulinDeliveryRemovesById() {
        var state: DirectState = makeState()
        let keep = InsulinDelivery(starts: Date(), ends: Date(), units: 2.0, type: .mealBolus)
        let toDelete = InsulinDelivery(starts: Date(), ends: Date(), units: 12.0, type: .basal)
        state.insulinDeliveryValues = [keep, toDelete]
        reduce(&state, .deleteInsulinDelivery(insulinDelivery: toDelete))
        #expect(state.insulinDeliveryValues.count == 1)
        #expect(state.insulinDeliveryValues.first?.id == keep.id)
    }
}

// MARK: - HR Overlay Tests (DMNC-848)

@Suite("HR Overlay")
struct HROverlayTests {
    @Test("setShowHeartRateOverlay toggles the flag")
    func toggleHROverlay() {
        var state: DirectState = makeState()
        state.showHeartRateOverlay = false
        reduce(&state, .setShowHeartRateOverlay(enabled: true))
        #expect(state.showHeartRateOverlay == true)
        reduce(&state, .setShowHeartRateOverlay(enabled: false))
        #expect(state.showHeartRateOverlay == false)
    }
}

// MARK: - Marker Lane Position Tests (DMNC-848 D7)

@Suite("Marker Lane Position")
struct MarkerLanePositionTests {
    @Test("setMarkerLanePosition updates the preference")
    func setPosition() {
        var state: DirectState = makeState()
        state.markerLanePosition = .top
        reduce(&state, .setMarkerLanePosition(position: .bottom))
        #expect(state.markerLanePosition == .bottom)
        reduce(&state, .setMarkerLanePosition(position: .top))
        #expect(state.markerLanePosition == .top)
    }
}

// MARK: - View State Persistence Tests (DMNC-1293)

@Suite("View State Persistence")
struct ViewStatePersistenceTests {

    @Test("setSelectedReportType cycles through all values")
    func cycleReportType() {
        var state: DirectState = makeState()
        #expect(state.selectedReportType == .glucose)

        reduce(&state, .setSelectedReportType(reportType: .timeInRange))
        #expect(state.selectedReportType == .timeInRange)

        reduce(&state, .setSelectedReportType(reportType: .statistics))
        #expect(state.selectedReportType == .statistics)

        reduce(&state, .setSelectedReportType(reportType: .glucose))
        #expect(state.selectedReportType == .glucose)
    }

    @Test("setSelectedReportType persists to UserDefaults on AppState")
    func reportTypePersists() {
        let defaults = makeTestDefaults()
        var state: DirectState = AppState(defaults: defaults)
        reduce(&state, .setSelectedReportType(reportType: .statistics))
        #expect(defaults.selectedReportType == .statistics)

        // Simulate relaunch: new AppState reads the persisted value.
        let reloaded = AppState(defaults: defaults)
        #expect(reloaded.selectedReportType == .statistics)
    }

    @Test("setListSectionExpanded expands a section and leaves others untouched")
    func expandSection() {
        var state: DirectState = makeState()
        #expect(state.listSectionExpanded.isEmpty)

        reduce(&state, .setListSectionExpanded(sectionName: "Meals", isExpanded: true))
        #expect(state.listSectionExpanded["Meals"] == true)
        #expect(state.listSectionExpanded["CGM"] == nil)
    }

    @Test("setListSectionExpanded collapses a previously expanded section")
    func collapseSection() {
        var state: DirectState = makeState()
        reduce(&state, .setListSectionExpanded(sectionName: "CGM", isExpanded: true))
        reduce(&state, .setListSectionExpanded(sectionName: "CGM", isExpanded: false))
        #expect(state.listSectionExpanded["CGM"] == false)
    }

    @Test("listSectionExpanded persists to UserDefaults on AppState")
    func sectionExpandedPersists() {
        let defaults = makeTestDefaults()
        var state: DirectState = AppState(defaults: defaults)
        reduce(&state, .setListSectionExpanded(sectionName: "Meals", isExpanded: true))
        reduce(&state, .setListSectionExpanded(sectionName: "Insulin", isExpanded: true))

        let reloaded = AppState(defaults: defaults)
        #expect(reloaded.listSectionExpanded["Meals"] == true)
        #expect(reloaded.listSectionExpanded["Insulin"] == true)
        #expect(reloaded.listSectionExpanded["CGM"] == nil)
    }
}
