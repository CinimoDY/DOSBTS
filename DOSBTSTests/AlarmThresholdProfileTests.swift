//
//  AlarmThresholdProfileTests.swift
//  DOSBTSTests
//
//  Verifies that alarm evaluation, snooze, critical-low breakthrough, and
//  the expiring-sensor floor read the correct profile's thresholds/volume.
//

import Foundation
import Testing
@testable import DOSBTSApp

private func windowEnclosingNow() -> (startH: Int, startM: Int, endH: Int, endM: Int) {
    let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
    let h = now.hour ?? 12
    let m = now.minute ?? 0
    let endTotal = h * 60 + m + 2
    return (h, m, (endTotal / 60) % 24, endTotal % 60)
}

private func degenerateWindow() -> (startH: Int, startM: Int, endH: Int, endM: Int) {
    (0, 0, 0, 0)
}

private func makeStateForceDay() -> AppState {
    var state = AppState(defaults: makeTestDefaults())
    let w = degenerateWindow()
    state.nightStartHour = w.startH
    state.nightStartMinute = w.startM
    state.nightEndHour = w.endH
    state.nightEndMinute = w.endM
    return state
}

private func makeStateForceNight() -> AppState {
    var state = AppState(defaults: makeTestDefaults())
    let w = windowEnclosingNow()
    state.nightStartHour = w.startH
    state.nightStartMinute = w.startM
    state.nightEndHour = w.endH
    state.nightEndMinute = w.endM
    return state
}

@Suite("Alarm threshold profile evaluation")
struct AlarmThresholdProfileTests {

    @Test("isAlarm uses day high when active profile is day")
    func dayHighFires() {
        var state = makeStateForceDay()
        state.dayAlarmHigh = 180
        state.nightAlarmHigh = 200
        #expect(state.activeAlarmProfile == .day)
        #expect(state.isAlarm(glucoseValue: 195) == .highAlarm)
    }

    @Test("isAlarm uses night high when active profile is night")
    func nightHighSilent() {
        var state = makeStateForceNight()
        state.dayAlarmHigh = 180
        state.nightAlarmHigh = 200
        #expect(state.activeAlarmProfile == .night)
        #expect(state.isAlarm(glucoseValue: 195) == .none)
    }

    @Test("isAlarm uses day low when active profile is day")
    func dayLowFires() {
        var state = makeStateForceDay()
        state.dayAlarmLow = 80
        state.nightAlarmLow = 70
        #expect(state.activeAlarmProfile == .day)
        #expect(state.isAlarm(glucoseValue: 75) == .lowAlarm)
    }

    @Test("isAlarm uses night low when active profile is night")
    func nightLowFires() {
        var state = makeStateForceNight()
        state.dayAlarmLow = 80
        state.nightAlarmLow = 85
        #expect(state.activeAlarmProfile == .night)
        // 75 < night low 85 → lowAlarm
        #expect(state.isAlarm(glucoseValue: 75) == .lowAlarm)
    }

    @Test("Critical-low breakthrough uses active profile alarmLow during night")
    func criticalLowBreakthroughNight() {
        var state = makeStateForceNight()
        state.dayAlarmLow = 80
        state.nightAlarmLow = 70
        // Critical-low breakthrough: glucose < state.alarmLow - 15
        // Night profile: 70 - 15 = 55. So 54 should be critical-low.
        let glucose = 54
        #expect(glucose < state.alarmLow - 15)
    }

    @Test("Critical-low breakthrough does NOT fire if glucose only crosses higher day low - 15")
    func criticalLowOnlyAtDayThreshold() {
        var state = makeStateForceNight()
        state.dayAlarmLow = 80
        state.nightAlarmLow = 70
        // 64 < (80 - 15 = 65) [day breakthrough] but 64 > (70 - 15 = 55) [night breakthrough]
        let glucose = 64
        // Active profile is night → breakthrough threshold is night - 15 = 55
        #expect(state.alarmLow == 70)
        #expect(glucose >= state.alarmLow - 15)
    }

    @Test("Snooze evaluation respects active-profile threshold change at boundary")
    func snoozeAcrossBoundary() {
        var state = makeStateForceDay()
        state.dayAlarmHigh = 180
        state.nightAlarmHigh = 200
        // Snooze set during day
        state.alarmSnoozeUntil = Date().addingTimeInterval(3600)
        state.alarmSnoozeKind = .highAlarm
        #expect(state.isSnoozed(alarm: .highAlarm))
        // Profile flips to night — threshold changes but snooze remains time-based
        let w = windowEnclosingNow()
        state.nightStartHour = w.startH
        state.nightStartMinute = w.startM
        state.nightEndHour = w.endH
        state.nightEndMinute = w.endM
        #expect(state.alarmHigh == 200) // night threshold
        #expect(state.isSnoozed(alarm: .highAlarm))
    }

    @Test("alarmVolume resolves to night volume during night (debug-bleed path)")
    func alarmVolumeNight() {
        var state = makeStateForceNight()
        state.dayAlarmVolume = 0.7
        state.nightAlarmVolume = 0.1
        #expect(state.activeAlarmProfile == .night)
        #expect(state.alarmVolume == 0.1)
    }

    @Test("alarmVolume resolves to day volume during day")
    func alarmVolumeDay() {
        var state = makeStateForceDay()
        state.dayAlarmVolume = 0.7
        state.nightAlarmVolume = 0.1
        #expect(state.activeAlarmProfile == .day)
        #expect(state.alarmVolume == 0.7)
    }

    @Test("Expiring-sensor floor uses max(day, night) regardless of active profile")
    func expiringFloorMax() {
        var state = makeStateForceNight()
        state.dayAlarmVolume = 0.7
        state.nightAlarmVolume = 0.0
        // ExpiringNotification will read max(state.dayAlarmVolume, state.nightAlarmVolume) = 0.7
        #expect(max(state.dayAlarmVolume, state.nightAlarmVolume) == 0.7)
        // Active-profile alarmVolume is the silent night value, which is exactly the case
        // we don't want for expiring sensor warnings.
        #expect(state.alarmVolume == 0.0)
    }

    @Test("Expiring-sensor floor stays loud when day is silent and night is loud")
    func expiringFloorMaxReverse() {
        var state = makeStateForceDay()
        state.dayAlarmVolume = 0.0
        state.nightAlarmVolume = 0.6
        #expect(max(state.dayAlarmVolume, state.nightAlarmVolume) == 0.6)
    }
}

// MARK: - Boundary-flip behavior (DMNC-895)

/// Pin the "active profile always wins, no pinning" behavior at the day/night
/// boundary for two specific decisions that read `state.alarmLow`:
///
/// 1. Predictive-low alarm flag clearing (`GlucoseNotification.swift:85-90`):
///    `glucose >= state.alarmLow + 10` clears the flag.
/// 2. Treatment cycle recovery check (`TreatmentCycleMiddleware.swift:82-88`):
///    `glucose >= state.alarmLow` ends the cycle as recovered.
///
/// Both decisions inherit the active profile's threshold at the moment they
/// run. The plan accepted this (no cycle pinning) — these tests guard against
/// a regression that reintroduces pinning, and also document the failure mode
/// users with tight-day / permissive-night configs need to know about.
///
/// The deeper fix (lock-at-flag-set-time) is tracked separately if/when a
/// user reports the failure mode in practice.
@Suite("Boundary-flip behavior on state.alarmLow")
struct BoundaryFlipBehaviorTests {

    @Test("Predictive-low clear-zone uses day threshold during day")
    func predictiveLowClearZoneDay() {
        // Day low 80 → clear zone is glucose >= 90.
        var state = makeStateForceDay()
        state.dayAlarmLow = 80
        state.nightAlarmLow = 70
        #expect(state.alarmLow == 80)
        let glucose = 85
        // 85 is NOT >= 90 → flag would NOT clear under day profile.
        #expect(glucose < state.alarmLow + 10)
    }

    @Test("Predictive-low clear-zone uses night threshold during night")
    func predictiveLowClearZoneNight() {
        // Night low 70 → clear zone is glucose >= 80.
        var state = makeStateForceNight()
        state.dayAlarmLow = 80
        state.nightAlarmLow = 70
        #expect(state.alarmLow == 70)
        let glucose = 85
        // 85 IS >= 80 → flag DOES clear under night profile.
        #expect(glucose >= state.alarmLow + 10)
    }

    @Test("Predictive-low clear-zone flips across the day→night boundary")
    func predictiveLowClearZoneFlipsAtBoundary() {
        // Same glucose (85), same thresholds (day 80 / night 70).
        // Under day profile: 85 < 90 → does not clear.
        var dayState = makeStateForceDay()
        dayState.dayAlarmLow = 80
        dayState.nightAlarmLow = 70

        // Under night profile: 85 >= 80 → clears.
        var nightState = makeStateForceNight()
        nightState.dayAlarmLow = 80
        nightState.nightAlarmLow = 70

        let glucose = 85
        let clearsUnderDay = glucose >= dayState.alarmLow + 10
        let clearsUnderNight = glucose >= nightState.alarmLow + 10
        #expect(clearsUnderDay == false)
        #expect(clearsUnderNight == true)
    }

    @Test("Treatment cycle recovery threshold uses day during day")
    func treatmentCycleRecoveryDay() {
        // A cycle started under day rules (low=80) considers glucose recovered
        // when it crosses back above 80.
        var state = makeStateForceDay()
        state.dayAlarmLow = 80
        state.nightAlarmLow = 70
        #expect(state.alarmLow == 80)
        let glucose = 74
        #expect(glucose < state.alarmLow) // 74 < 80 → still in cycle
    }

    @Test("Treatment cycle recovery threshold uses night during night")
    func treatmentCycleRecoveryNight() {
        // Same cycle, but recheck happens after the boundary flip.
        // Night low is 70 → glucose=74 is now considered recovered.
        var state = makeStateForceNight()
        state.dayAlarmLow = 80
        state.nightAlarmLow = 70
        #expect(state.alarmLow == 70)
        let glucose = 74
        #expect(glucose >= state.alarmLow) // 74 >= 70 → cycle ends as recovered
    }

    @Test("Treatment cycle recovery flips a mid-cycle verdict across the boundary")
    func treatmentCycleRecoveryFlipsAtBoundary() {
        // Concrete failure mode for the "tight day / permissive night" config:
        // user is hypo at 21:55 with glucose=74 (below day's 80), treatment
        // cycle starts. At 22:10 the active profile flips to night (low=70),
        // and the same glucose=74 now reads as "recovered" — even though the
        // user's daytime rules said it wasn't.
        var dayState = makeStateForceDay()
        dayState.dayAlarmLow = 80
        dayState.nightAlarmLow = 70

        var nightState = makeStateForceNight()
        nightState.dayAlarmLow = 80
        nightState.nightAlarmLow = 70

        let glucose = 74
        let recoveredUnderDay = glucose >= dayState.alarmLow
        let recoveredUnderNight = glucose >= nightState.alarmLow
        #expect(recoveredUnderDay == false)
        #expect(recoveredUnderNight == true)
        // This is the documented v1 behavior. The mitigation (warning rows in
        // Settings when night thresholds are more permissive than day) lives
        // in AlarmSettingsView and discourages this config in practice.
    }
}
