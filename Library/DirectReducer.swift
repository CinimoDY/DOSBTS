//
//  DefaultAppReducer.swift
//  DOSBTS
//

import Combine
import Foundation
import UIKit

// MARK: - directReducer

func directReducer(state: inout DirectState, action: DirectAction) {
    if !Thread.isMainThread {
        DirectLog.error("Reducer is not used in main thread, action: \(action), queue: \(OperationQueue.current?.underlyingQueue?.label ?? "None")")
    }
    
    switch action {
    case .addCalibration(bloodGlucoseValue: let bloodGlucoseValue):
        guard let latestGlucoseValue = state.sensorGlucoseValues.last?.rawGlucoseValue else {
            DirectLog.info("Guard: state.currentGlucose.initialGlucoseValue is nil")
            break
        }
        
        state.customCalibration.append(CustomCalibration(x: Double(latestGlucoseValue), y: Double(bloodGlucoseValue)))
        
    case .addBloodGlucose(glucoseValues: let glucoseValues):
        state.latestBloodGlucose = glucoseValues.last
        
    case .addInsulinDelivery(insulinDeliveryValues: let insulinDeliveryValues):
        state.latestInsulinDelivery = insulinDeliveryValues.last
        // Optimistic append — the marker shows on the chart immediately.
        // The middleware-triggered .loadInsulinDeliveryValues round-trip
        // will subsequently replace this with the canonical DB state.
        state.insulinDeliveryValues.append(contentsOf: insulinDeliveryValues)

    case .addMealEntry(mealEntryValues: let mealEntryValues):
        // Optimistic append — same rationale as .addInsulinDelivery above.
        state.mealEntryValues.append(contentsOf: mealEntryValues)

    case .addSensorGlucose(glucoseValues: let glucoseValues):
        state.latestSensorGlucose = glucoseValues.last
        state.connectionError = nil
        state.connectionErrorTimestamp = nil
        
    case .addSensorError(errorValues: let errorValues):
        state.latestSensorError = errorValues.last
        
    case .clearCalibrations:
        state.customCalibration = []
        
    case .clearBloodGlucoseValues:
        state.latestBloodGlucose = nil
        
    case .clearSensorGlucoseValues:
        state.latestSensorGlucose = nil
        
    case .clearSensorErrorValues:
        state.latestSensorError = nil
        
    case .registerConnectionInfo(infos: let infos):
        state.connectionInfos.append(contentsOf: infos)
        
    case .deleteCalibration(calibration: let calibration):
        state.customCalibration = state.customCalibration.filter { item in
            item.id != calibration.id
        }
        
    case .resetSensor:
        state.sensor = nil
        state.customCalibration = []
        state.connectionError = nil
        state.connectionErrorTimestamp = nil
        
    case .resetError:
        state.connectionError = nil
        state.connectionErrorTimestamp = nil
        
    case .selectCalendarTarget(id: let id):
        state.selectedCalendarTarget = id
        
    case .selectConnection(id: let id, connection: let connection):
        if id != state.selectedConnectionID || state.selectedConnection == nil {
            state.selectedConnectionID = id
            state.selectedConnection = connection
            
            if let sensor = state.sensor {
                state.selectedConfiguration = connection.getConfiguration(sensor: sensor)
            }
        }
        
    case .selectConnectionID(id: _):
        state.isConnectionPaired = false
        state.sensor = nil
        state.transmitter = nil
        state.selectedConfiguration = []
        state.customCalibration = []
        state.connectionError = nil
        state.connectionErrorTimestamp = nil
        
    case .selectView(viewTag: let viewTag):
        state.selectedView = viewTag
        
    case .setDayAlarmHigh(value: let value):
        state.dayAlarmHigh = value

    case .setDayAlarmLow(value: let value):
        state.dayAlarmLow = value

    case .setDayAlarmVolume(value: let value):
        state.dayAlarmVolume = value

    case .setNightAlarmHigh(value: let value):
        state.nightAlarmHigh = value

    case .setNightAlarmLow(value: let value):
        state.nightAlarmLow = value

    case .setNightAlarmVolume(value: let value):
        state.nightAlarmVolume = value

    case .setNightScheduleStart(hour: let hour, minute: let minute):
        state.nightStartHour = hour
        state.nightStartMinute = minute

    case .setNightScheduleEnd(hour: let hour, minute: let minute):
        state.nightEndHour = hour
        state.nightEndMinute = minute
        
    case .setAlarmSnoozeUntil(untilDate: let untilDate, autosnooze: let autosnooze):
        if let untilDate = untilDate {
            state.alarmSnoozeUntil = untilDate
            
            if let glucose = state.sensorGlucoseValues.last {
                let alarm = state.isAlarm(glucoseValue: glucose.glucoseValue)
                
                if alarm != .none {
                    state.alarmSnoozeKind = alarm
                }
            }
            
            if !autosnooze {
                DirectNotifications.shared.stopSound()
            }
        } else {
            state.alarmSnoozeUntil = nil
            state.alarmSnoozeKind = nil
        }

    case .setAppleCalendarExport(enabled: let enabled):
        state.appleCalendarExport = enabled
        
    case .setAppleHealthExport(enabled: let enabled):
        state.appleHealthExport = enabled

    case .setAppleHealthImport(enabled: let enabled):
        state.appleHealthImport = enabled
        
    case .setAppState(appState: let appState):
        state.appState = appState
        
    case .setBellmanConnectionState(connectionState: let connectionState):
        state.bellmanConnectionState = connectionState
        
    case .setBellmanNotification(enabled: let enabled):
        state.bellmanAlarm = enabled
           
    case .setChartShowLines(enabled: let enabled):
        state.chartShowLines = enabled
        
    case .setChartZoomLevel(level: let level):
        state.chartZoomLevel = level
        
    case .setConnectionAlarmSound(sound: let sound):
        state.connectionAlarmSound = sound
        
    case .setIgnoreMute(enabled: let enabled):
        state.ignoreMute = enabled
        
    case .setConnectionError(errorMessage: let errorMessage, errorTimestamp: let errorTimestamp):
        state.connectionError = errorMessage
        state.connectionErrorTimestamp = errorTimestamp
        
    case .setConnectionPaired(isPaired: let isPaired):
        state.isConnectionPaired = isPaired
        
    case .setConnectionPeripheralUUID(peripheralUUID: let peripheralUUID):
        state.connectionPeripheralUUID = peripheralUUID
        
    case .setConnectionState(connectionState: let connectionState):
        state.connectionState = connectionState

        if resetableStates.contains(connectionState) {
            state.connectionError = nil
            state.connectionErrorTimestamp = nil
        }
        
    case .setExpiringAlarmSound(sound: let sound):
        state.expiringAlarmSound = sound
               
    case .setNormalGlucoseNotification(enabled: let enabled):
        state.normalGlucoseNotification = enabled
        
    case .setAlarmGlucoseNotification(enabled: let enabled):
        state.alarmGlucoseNotification = enabled
        
    case .setGlucoseLiveActivity(enabled: let enabled):
        state.glucoseLiveActivity = enabled
        
    case .setGlucoseUnit(unit: let unit):
        state.glucoseUnit = unit

    case .setBloodGlucoseValues(glucoseValues: let glucoseValues):
        state.bloodGlucoseValues = glucoseValues
        
    case .setInsulinDeliveryValues(insulinDeliveryValues: let insulinDeliveryValues):
        state.insulinDeliveryValues = insulinDeliveryValues

    case .setExerciseEntryValues(exerciseEntryValues: let exerciseEntryValues):
        state.exerciseEntryValues = exerciseEntryValues

    case .setHeartRateSeries(heartRateSeries: let heartRateSeries):
        state.heartRateSeries = heartRateSeries

    case .setHealthImportExcludedSources(excludedSources: let excludedSources):
        state.healthImportExcludedSources = excludedSources

    case .setFavoriteFoodValues(favoriteFoodValues: let favoriteFoodValues):
        state.favoriteFoodValues = favoriteFoodValues

    case .setPersonalFoods(personalFoods: let personalFoods):
        state.personalFoodValues = personalFoods

    case .setScoredPersonalFoods(scoredPersonalFoods: let scoredPersonalFoods):
        state.scoredPersonalFoodValues = scoredPersonalFoods

    case .setRecentFoodCorrections(recentFoodCorrections: let recentFoodCorrections):
        state.recentFoodCorrections = recentFoodCorrections

    case .setServingPresets(servingPresets: let servingPresets):
        state.servingPresets = servingPresets

    case .setRecentMealEntries(recentMealEntries: let recentMealEntries):
        state.recentMealEntries = recentMealEntries

    case .setMealEntryValues(mealEntryValues: let mealEntryValues):
        state.mealEntryValues = mealEntryValues

    case .setSensorGlucoseValues(glucoseValues: let glucoseValues):
        state.sensorGlucoseValues = glucoseValues
        
        #if targetEnvironment(simulator)
        if state.latestSensorGlucose == nil {
            state.latestSensorGlucose = glucoseValues.last
        }
        #endif
        
    case .setSensorErrorValues(errorValues: let errorValues):
        state.sensorErrorValues = errorValues
        
    case .setHighGlucoseAlarmSound(sound: let sound):
        state.highGlucoseAlarmSound = sound

    case .setLowGlucoseAlarmSound(sound: let sound):
        state.lowGlucoseAlarmSound = sound

    case .setNightscoutSecret(apiSecret: let apiSecret):
        state.nightscoutApiSecret = apiSecret

    case .setNightscoutUpload(enabled: let enabled):
        state.nightscoutUpload = enabled
        
    case .setNightscoutURL(url: let url):
        state.nightscoutURL = url
        
    case .setPreventScreenLock(enabled: let enabled):
        state.preventScreenLock = enabled

    case .setReadGlucose(enabled: let enabled):
        state.readGlucose = enabled
        
    case .setMinSelectedDate(minSelectedDate: let minSelectedDate):
        state.minSelectedDate = min(minSelectedDate, state.minSelectedDate)
        
    case .setSelectedDate(selectedDate: let date):
        if let date = date, date < Date().startOfDay {
            state.selectedDate = date
        } else {
            state.selectedDate = nil
        }
        
    case .setSensor(sensor: let sensor, keepDevice: let keepDevice):
        if let sensorSerial = state.sensor?.serial, sensorSerial != sensor.serial {
            state.customCalibration = []
            
            if !keepDevice {
                state.connectionPeripheralUUID = nil
            }
        }
        
        state.sensor = sensor
        state.connectionError = nil
        state.connectionErrorTimestamp = nil
        
        if let selectedConnection = state.selectedConnection {
            state.selectedConfiguration = selectedConnection.getConfiguration(sensor: sensor)
        }
        
    case .setSensorInterval(interval: let interval):
        state.sensorInterval = interval

    case .setSensorState(sensorAge: let sensorAge, sensorState: let sensorState):
        guard state.sensor != nil else {
            DirectLog.info("Guard: state.sensor is nil")
            break
        }
        
        state.sensor!.age = sensorAge
        
        if let sensorState = sensorState {
            state.sensor!.state = sensorState
        }
        
        if state.sensor!.startTimestamp == nil, sensorAge > state.sensor!.warmupTime {
            state.sensor!.startTimestamp = Date().toRounded(on: 1, .minute) - Double(sensorAge * 60)
        }
        
        state.connectionError = nil
        state.connectionErrorTimestamp = nil
        
    case .setShowAnnotations(showAnnotations: let showAnnotations):
        state.showAnnotations = showAnnotations
        
    case .setGlucoseStatistics(statistics: let statistics):
        state.glucoseStatistics = statistics

    case .setTransmitter(transmitter: let transmitter):
        state.transmitter = transmitter
        
    case .setStatisticsDays(days: let days):
        state.statisticsDays = days

    case .exportToUnknown:
        state.appIsBusy = true

    case .exportToTidepool:
        state.appIsBusy = true
        
    case .exportToGlooko:
        state.appIsBusy = true

    case .generateClinicReport:
        state.appIsBusy = true

    case .sendFile(fileURL: _):
        state.appIsBusy = false
        
    case .setAppIsBusy(isBusy: let isBusy):
        state.appIsBusy = isBusy
        
    case .setShowSmoothedGlucose(enabled: let enabled):
        state.showSmoothedGlucose = enabled
        
    case .setShowInsulinInput(enabled: let enabled):
        state.showInsulinInput = enabled

    case .setShowScanlines(enabled: let enabled):
        state.showScanlines = enabled

    case .setAIConsentFoodPhoto(enabled: let enabled):
        state.aiConsentFoodPhoto = enabled

    case .setHasSeenBGRelocationHint(seen: let seen):
        state.hasSeenBGRelocationHint = seen

    case .incrementAppOpenCount:
        state.appOpenCount += 1
        if state.appOpenCountFirstRecordedAt == nil {
            state.appOpenCountFirstRecordedAt = Date()
        }

    case .setClaudeAPIKeyValid(isValid: let isValid):
        state.claudeAPIKeyValid = isValid

    case .setFoodAnalysisResult(result: let result):
        state.foodAnalysisResult = result
        state.foodAnalysisLoading = false
        state.foodAnalysisError = nil

    case .setFoodAnalysisError(error: let error):
        state.foodAnalysisError = error
        state.foodAnalysisLoading = false

    case .setFoodAnalysisLoading(isLoading: let isLoading):
        state.foodAnalysisLoading = isLoading
        if isLoading {
            state.foodAnalysisResult = nil
            state.foodAnalysisError = nil
        }

    case .setThumbCalibration(widthMM: let widthMM):
        state.thumbCalibrationMM = widthMM

    // MARK: Treatment Cycle
    case .showTreatmentPrompt(alarmFiredAt: let alarmFiredAt):
        state.showTreatmentPrompt = true
        state.alarmFiredAt = alarmFiredAt

    case .setShowTreatmentPrompt(show: let show):
        state.showTreatmentPrompt = show

    case .logHypoTreatment(favorite: _, alarmFiredAt: _, overrideTimestamp: let overrideTimestamp):
        state.treatmentLoggedAt = overrideTimestamp ?? Date()
        state.showTreatmentPrompt = false
        state.recheckDispatched = false
        // Clear stale countdown expiry to prevent race: next addSensorGlucose arriving before
        // startTreatmentCycle could see the old (expired) expiry and fire a premature recheck.
        state.treatmentCycleCountdownExpiry = nil

    case .startTreatmentCycle:
        state.treatmentCycleActive = true
        state.recheckDispatched = false
        state.treatmentCycleCountdownExpiry = Date().addingTimeInterval(Double(state.hypoTreatmentWaitMinutes * 60))
        state.treatmentCycleSnoozeUntil = state.treatmentCycleCountdownExpiry

    case .endTreatmentCycle:
        state.treatmentCycleActive = false
        state.alarmFiredAt = nil
        state.treatmentLoggedAt = nil
        state.treatmentCycleCountdownExpiry = nil
        state.treatmentCycleSnoozeUntil = nil
        state.recheckDispatched = false

    case .dismissTreatmentCycle:
        state.treatmentCycleActive = false
        state.showTreatmentPrompt = false
        state.alarmFiredAt = nil
        state.treatmentLoggedAt = nil
        state.treatmentCycleCountdownExpiry = nil
        state.treatmentCycleSnoozeUntil = nil
        state.recheckDispatched = false

    case .treatmentCycleRecovered(glucoseValue: _):
        state.recheckDispatched = true

    case .treatmentCycleStillLow(glucoseValue: _):
        state.recheckDispatched = true
        state.showTreatmentPrompt = true

    case .setHypoTreatmentWaitMinutes(minutes: let minutes):
        state.hypoTreatmentWaitMinutes = minutes

    // MARK: Predictive Low Alarm
    case .setShowPredictiveLowAlarm(enabled: let enabled):
        state.showPredictiveLowAlarm = enabled

    case .setPredictiveLowAlarmFired(fired: let fired):
        state.predictiveLowAlarmFired = fired

    // MARK: Missed-Bolus Nudge (DMNC-1300)
    case .setShowMissedBolusNudge(enabled: let enabled):
        state.showMissedBolusNudge = enabled

    // MARK: Celebrations (DMNC-772)
    case .setShowCelebrations(enabled: let enabled):
        state.showCelebrations = enabled

    case .tightControlStreakCelebrated(streakStart: let streakStart, deferred: let deferred):
        state.tightControlStreakCount += 1
        state.tightControlLastCelebratedStreakStart = streakStart
        if deferred {
            state.tightControlPendingCelebrationCount += 1
        }

    case .setTightControlLastCelebratedStreakStart(start: let start):
        state.tightControlLastCelebratedStreakStart = start

    case .clearTightControlPendingCelebrations:
        state.tightControlPendingCelebrationCount = 0

    case .presentTightControlCelebration(celebration: let celebration):
        state.tightControlCelebration = celebration

    case .clearTightControlCelebration:
        state.tightControlCelebration = nil

    // MARK: View State Persistence (DMNC-1293)
    case .setSelectedReportType(reportType: let reportType):
        state.selectedReportType = reportType

    case .setListSectionExpanded(sectionName: let sectionName, isExpanded: let isExpanded):
        state.listSectionExpanded[sectionName] = isExpanded

    // MARK: What's New / changelog (DMNC-1147)
    case .setLastSeenBuild(build: let build):
        state.lastSeenBuild = build

    case .setSettingsCategory(category: let category):
        state.selectedSettingsCategory = category

    // MARK: Heart Rate Overlay (DMNC-848)
    case .setShowHeartRateOverlay(enabled: let enabled):
        state.showHeartRateOverlay = enabled

    // MARK: Marker Lane Position (DMNC-848 D7)
    case .setMarkerLanePosition(position: let position):
        state.markerLanePosition = position

    // MARK: IOB
    case .setBolusInsulinPreset(preset: let preset):
        state.bolusInsulinPreset = preset

    case .setBasalDIAMinutes(minutes: let minutes):
        state.basalDIAMinutes = minutes

    case .setShowSplitIOB(enabled: let enabled):
        state.showSplitIOB = enabled

    case .setIOBDeliveries(deliveries: let deliveries):
        state.iobDeliveries = deliveries

    // MARK: Ratio Lab
    case .setRatioEvidence(evidence: let evidence):
        state.ratioEvidence = evidence

    case .setConfirmedICR(icr: let icr):
        state.confirmedICR = icr

    // MARK: Meal Impact
    case .setScoredMealEntryIds(scoredMealEntryIds: let ids):
        state.scoredMealEntryIds = ids

    // MARK: Daily Digest
    case .loadDailyDigest:
        state.dailyDigestLoading = true

    case .setDailyDigest(digest: let digest):
        state.currentDailyDigest = digest
        state.dailyDigestLoading = false

    case .setDailyDigestError:
        state.dailyDigestLoading = false

    case .generateDailyDigestInsight:
        state.dailyDigestInsightLoading = true

    case .setDailyDigestInsight(date: _, insight: let insight):
        state.currentDailyDigest?.aiInsight = insight
        state.currentDailyDigest?.generatedAt = Date()
        state.dailyDigestInsightLoading = false

    case .setDailyDigestInsightError:
        state.dailyDigestInsightLoading = false

    case .setDailyDigestEvents(events: let events):
        state.dailyDigestEvents = events

    case .setAIConsentDailyDigest(enabled: let enabled):
        state.aiConsentDailyDigest = enabled

    case .setDailyDigestReminderTime(hour: let hour, minute: let minute):
        state.dailyDigestReminderHour = hour
        state.dailyDigestReminderMinute = minute

    // MARK: Update + Delete Actions — optimistic in-memory mutation so chart
    // markers and entry rows refresh in the same runloop tick as the dispatch.
    // The middleware-triggered .load*Values round-trip will subsequently
    // re-sync from GRDB (defensive) but the UI no longer waits on the
    // write+read latency for the marker to appear / update / disappear (DMNC-905).
    case .updateMealEntry(mealEntry: let updated):
        if let idx = state.mealEntryValues.firstIndex(where: { $0.id == updated.id }) {
            state.mealEntryValues[idx] = updated
        } else {
            state.mealEntryValues.append(updated)
        }

    case .updateInsulinDelivery(insulinDelivery: let updated):
        if let idx = state.insulinDeliveryValues.firstIndex(where: { $0.id == updated.id }) {
            state.insulinDeliveryValues[idx] = updated
        } else {
            state.insulinDeliveryValues.append(updated)
        }

    case .deleteMealEntry(mealEntry: let toDelete):
        state.mealEntryValues.removeAll(where: { $0.id == toDelete.id })

    case .deleteInsulinDelivery(insulinDelivery: let toDelete):
        state.insulinDeliveryValues.removeAll(where: { $0.id == toDelete.id })

    default:
        break
    }

    if let alarmSnoozeUntil = state.alarmSnoozeUntil, Date() > alarmSnoozeUntil {
        state.alarmSnoozeUntil = nil
        state.alarmSnoozeKind = nil
    }
}

// MARK: - private

private var resetableStates: Set<SensorConnectionState> = [.connected, .powerOff, .scanning]
private var disconnectedStates: Set<SensorConnectionState> = [.disconnected, .scanning]
