//
//  AlarmProfileMigrationTests.swift
//  DOSBTSTests
//
//  Verifies the once-per-install migration that copies legacy alarm settings
//  into both day and night profiles, and the dual-write rollback safety
//  behavior on day-side setters.
//
//  Each test injects a fresh UserDefaults suite (makeTestDefaults, defined in
//  DirectReducerTests.swift) so tests are isolated from each other, from
//  parallel suites, and from previous runs.
//

import Foundation
import Testing
@testable import DOSBTSApp

private let legacyHighKey = "libre-direct.settings.alarm-high"
private let legacyLowKey = "libre-direct.settings.alarm-low"
private let legacyVolumeKey = "libre-direct.settings.alarm-volume"
private let dayHighKey = "libre-direct.settings.day-alarm-high"
private let dayLowKey = "libre-direct.settings.day-alarm-low"
private let dayVolumeKey = "libre-direct.settings.day-alarm-volume"
private let nightHighKey = "libre-direct.settings.night-alarm-high"
private let nightLowKey = "libre-direct.settings.night-alarm-low"
private let nightVolumeKey = "libre-direct.settings.night-alarm-volume"
private let nightStartHourKey = "libre-direct.settings.night-start-hour"
private let nightStartMinuteKey = "libre-direct.settings.night-start-minute"
private let nightEndHourKey = "libre-direct.settings.night-end-hour"
private let nightEndMinuteKey = "libre-direct.settings.night-end-minute"

@Suite("AlarmProfile migration")
struct AlarmProfileMigrationTests {

    @Test("Fresh install seeds defaults for both profiles + schedule")
    func freshInstall() {
        let defaults = makeTestDefaults()

        _ = AppState(defaults: defaults)

        #expect(defaults.integer(forKey: dayHighKey) == 180)
        #expect(defaults.integer(forKey: nightHighKey) == 180)
        #expect(defaults.integer(forKey: dayLowKey) == 80)
        #expect(defaults.integer(forKey: nightLowKey) == 80)
        #expect(abs(defaults.float(forKey: dayVolumeKey) - 0.2) < 0.0001)
        #expect(abs(defaults.float(forKey: nightVolumeKey) - 0.2) < 0.0001)
        #expect(defaults.integer(forKey: nightStartHourKey) == 22)
        #expect(defaults.integer(forKey: nightStartMinuteKey) == 0)
        #expect(defaults.integer(forKey: nightEndHourKey) == 7)
        #expect(defaults.integer(forKey: nightEndMinuteKey) == 0)
    }

    @Test("Legacy install copies threshold + volume into both profiles")
    func legacyCopy() {
        let defaults = makeTestDefaults()
        defaults.set(195, forKey: legacyHighKey)
        defaults.set(75, forKey: legacyLowKey)
        defaults.set(Float(0.65), forKey: legacyVolumeKey)

        _ = AppState(defaults: defaults)

        #expect(defaults.integer(forKey: dayHighKey) == 195)
        #expect(defaults.integer(forKey: nightHighKey) == 195)
        #expect(defaults.integer(forKey: dayLowKey) == 75)
        #expect(defaults.integer(forKey: nightLowKey) == 75)
        #expect(abs(defaults.float(forKey: dayVolumeKey) - 0.65) < 0.0001)
        #expect(abs(defaults.float(forKey: nightVolumeKey) - 0.65) < 0.0001)
        // Schedule defaults are seeded regardless of legacy state
        #expect(defaults.integer(forKey: nightStartHourKey) == 22)
        #expect(defaults.integer(forKey: nightEndHourKey) == 7)
    }

    @Test("Migration is idempotent — second launch preserves user-tweaked night values")
    func idempotentBasic() {
        let defaults = makeTestDefaults()
        // Simulate a completed migration with tweaked night thresholds
        defaults.set(180, forKey: dayHighKey)
        defaults.set(220, forKey: nightHighKey)
        defaults.set(80, forKey: dayLowKey)
        defaults.set(85, forKey: nightLowKey)
        defaults.set(Float(0.5), forKey: dayVolumeKey)
        defaults.set(Float(0.0), forKey: nightVolumeKey)
        defaults.set(23, forKey: nightStartHourKey)
        defaults.set(30, forKey: nightStartMinuteKey)
        defaults.set(6, forKey: nightEndHourKey)
        defaults.set(45, forKey: nightEndMinuteKey)

        _ = AppState(defaults: defaults)

        #expect(defaults.integer(forKey: nightHighKey) == 220)
        #expect(defaults.integer(forKey: nightLowKey) == 85)
        #expect(defaults.float(forKey: nightVolumeKey) == 0)
        #expect(defaults.integer(forKey: nightStartHourKey) == 23)
        #expect(defaults.integer(forKey: nightStartMinuteKey) == 30)
        #expect(defaults.integer(forKey: nightEndHourKey) == 6)
        #expect(defaults.integer(forKey: nightEndMinuteKey) == 45)
    }

    @Test("Migration is idempotent even after legacy key dual-write")
    func idempotentAfterDualWrite() {
        let defaults = makeTestDefaults()
        // After first migration + a day-side edit, the legacy alarmHigh key
        // is present (dual-write side effect) AND dayAlarmHigh is present.
        defaults.set(170, forKey: dayHighKey)  // user edited via Day picker
        defaults.set(170, forKey: legacyHighKey)  // dual-write echo
        defaults.set(220, forKey: nightHighKey)  // user-customised night
        defaults.set(80, forKey: dayLowKey)
        defaults.set(80, forKey: nightLowKey)
        defaults.set(Float(0.5), forKey: dayVolumeKey)
        defaults.set(Float(0.5), forKey: nightVolumeKey)

        _ = AppState(defaults: defaults)

        // Night high should still be the user's customised value, not overwritten
        // back to the legacy 170.
        #expect(defaults.integer(forKey: nightHighKey) == 220)
        #expect(defaults.integer(forKey: dayHighKey) == 170)
    }
}

@Suite("AlarmProfile dual-write rollback safety")
struct AlarmProfileDualWriteTests {

    @Test("setDayAlarmHigh writes both day and legacy keys")
    func dayAlarmHighDualWrites() {
        let defaults = makeTestDefaults()
        var state: DirectState = AppState(defaults: defaults)
        directReducer(state: &state, action: .setDayAlarmHigh(value: 175))

        #expect(defaults.integer(forKey: dayHighKey) == 175)
        #expect(defaults.integer(forKey: legacyHighKey) == 175)
    }

    @Test("setDayAlarmLow writes both day and legacy keys")
    func dayAlarmLowDualWrites() {
        let defaults = makeTestDefaults()
        var state: DirectState = AppState(defaults: defaults)
        directReducer(state: &state, action: .setDayAlarmLow(value: 72))

        #expect(defaults.integer(forKey: dayLowKey) == 72)
        #expect(defaults.integer(forKey: legacyLowKey) == 72)
    }

    @Test("setDayAlarmVolume writes both day and legacy keys")
    func dayAlarmVolumeDualWrites() {
        let defaults = makeTestDefaults()
        var state: DirectState = AppState(defaults: defaults)
        directReducer(state: &state, action: .setDayAlarmVolume(value: 0.65))

        #expect(abs(defaults.float(forKey: dayVolumeKey) - 0.65) < 0.0001)
        #expect(abs(defaults.float(forKey: legacyVolumeKey) - 0.65) < 0.0001)
    }

    @Test("setNightAlarmHigh writes only night key (no legacy mirror)")
    func nightAlarmHighSingleWrite() {
        let defaults = makeTestDefaults()
        var state: DirectState = AppState(defaults: defaults)
        // After init the migration copies whatever is in legacy (or defaults) to legacy too.
        // To verify the night-side does NOT touch the legacy key, we record its value first.
        let legacyBefore = defaults.integer(forKey: legacyHighKey)
        directReducer(state: &state, action: .setNightAlarmHigh(value: 215))

        #expect(defaults.integer(forKey: nightHighKey) == 215)
        #expect(defaults.integer(forKey: legacyHighKey) == legacyBefore)
    }
}
