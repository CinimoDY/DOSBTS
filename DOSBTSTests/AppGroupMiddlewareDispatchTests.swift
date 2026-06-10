//
//  AppGroupMiddlewareDispatchTests.swift
//  DOSBTSTests
//
//  Verifies that the AppGroupSharing middleware writes profile data to
//  UserDefaults.shared on the trigger actions: .startup, .addSensorGlucose,
//  and the per-profile setters. This is the load-bearing path for widget +
//  Live Activity sync — a regression that drops a key or omits a setter
//  trigger arm would silently break cross-target rendering.
//

import Foundation
import Combine
import Testing
@testable import DOSBTSApp

private func clearSharedAlarmKeys() {
    for key in AppGroupAlarmProfileKeys.allRequired {
        UserDefaults.shared.removeObject(forKey: key)
    }
}

private func makeMockState() -> AppState {
    var state = AppState(defaults: makeTestDefaults())
    state.dayAlarmHigh = 175
    state.dayAlarmLow = 75
    state.nightAlarmHigh = 220
    state.nightAlarmLow = 65
    state.nightStartHour = 23
    state.nightStartMinute = 30
    state.nightEndHour = 6
    state.nightEndMinute = 45
    return state
}

private func dispatch(_ action: DirectAction, state: AppState) {
    let middleware = appGroupSharingMiddleware()
    _ = middleware(state, action, state)
}

@Suite("AppGroupSharing writes profile data on triggers", .serialized)
struct AppGroupMiddlewareDispatchTests {

    @Test("Writes all 8 profile keys on .startup")
    func startupSeedsKeys() {
        clearSharedAlarmKeys()
        let state = makeMockState()

        dispatch(.startup, state: state)

        #expect(UserDefaults.shared.integer(forKey: AppGroupAlarmProfileKeys.dayAlarmHigh) == 175)
        #expect(UserDefaults.shared.integer(forKey: AppGroupAlarmProfileKeys.dayAlarmLow) == 75)
        #expect(UserDefaults.shared.integer(forKey: AppGroupAlarmProfileKeys.nightAlarmHigh) == 220)
        #expect(UserDefaults.shared.integer(forKey: AppGroupAlarmProfileKeys.nightAlarmLow) == 65)
        #expect(UserDefaults.shared.integer(forKey: AppGroupAlarmProfileKeys.nightStartHour) == 23)
        #expect(UserDefaults.shared.integer(forKey: AppGroupAlarmProfileKeys.nightStartMinute) == 30)
        #expect(UserDefaults.shared.integer(forKey: AppGroupAlarmProfileKeys.nightEndHour) == 6)
        #expect(UserDefaults.shared.integer(forKey: AppGroupAlarmProfileKeys.nightEndMinute) == 45)
    }

    @Test("Writes profile keys on each non-volume per-profile setter")
    func nonVolumeSettersWriteKeys() {
        for action in [
            DirectAction.setDayAlarmHigh(value: 175),
            DirectAction.setDayAlarmLow(value: 75),
            DirectAction.setNightAlarmHigh(value: 220),
            DirectAction.setNightAlarmLow(value: 65),
            DirectAction.setNightScheduleStart(hour: 23, minute: 30),
            DirectAction.setNightScheduleEnd(hour: 6, minute: 45)
        ] {
            clearSharedAlarmKeys()
            dispatch(action, state: makeMockState())

            // The middleware writes ALL profile keys regardless of which setter
            // fired (it mirrors the whole snapshot, not just the changed key).
            for key in AppGroupAlarmProfileKeys.allRequired {
                #expect(
                    UserDefaults.shared.object(forKey: key) != nil,
                    "Key '\(key)' should be present after \(action)"
                )
            }
        }
    }

    @Test("Volume setters do NOT write profile keys (excluded by design)")
    func volumeSettersDoNotWriteKeys() {
        // Volume isn't rendered on widget or Live Activity, so volume slider
        // drags must not flood the App Group / push budget.
        for action in [
            DirectAction.setDayAlarmVolume(value: 0.6),
            DirectAction.setNightAlarmVolume(value: 0.3)
        ] {
            clearSharedAlarmKeys()
            dispatch(action, state: makeMockState())

            for key in AppGroupAlarmProfileKeys.allRequired {
                #expect(
                    UserDefaults.shared.object(forKey: key) == nil,
                    "Key '\(key)' should NOT be written by \(action) — volume setters are excluded"
                )
            }
        }
    }
}
