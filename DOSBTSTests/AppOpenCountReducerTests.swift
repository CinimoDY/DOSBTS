//
//  AppOpenCountReducerTests.swift
//  DOSBTSTests
//

import Foundation
import Testing
@testable import DOSBTSApp

private func makeAppOpenState() -> AppState {
    AppState(defaults: makeTestDefaults())
}

private func reduceAppOpen(_ state: inout DirectState, _ action: DirectAction) {
    directReducer(state: &state, action: action)
}

@Suite("App open count")
struct AppOpenCountReducerTests {

    @Test("incrementAppOpenCount increases the counter from zero")
    func incrementsFromZero() {
        var state: DirectState = makeAppOpenState()
        state.appOpenCount = 0
        state.appOpenCountFirstRecordedAt = nil
        reduceAppOpen(&state, .incrementAppOpenCount)
        #expect(state.appOpenCount == 1)
    }

    @Test("incrementAppOpenCount increases the counter each call")
    func incrementsRepeatedly() {
        var state: DirectState = makeAppOpenState()
        state.appOpenCount = 0
        state.appOpenCountFirstRecordedAt = nil
        reduceAppOpen(&state, .incrementAppOpenCount)
        reduceAppOpen(&state, .incrementAppOpenCount)
        reduceAppOpen(&state, .incrementAppOpenCount)
        #expect(state.appOpenCount == 3)
    }

    @Test("first increment sets appOpenCountFirstRecordedAt")
    func firstIncrementRecordsStartDate() {
        var state: DirectState = makeAppOpenState()
        state.appOpenCount = 0
        state.appOpenCountFirstRecordedAt = nil
        reduceAppOpen(&state, .incrementAppOpenCount)
        #expect(state.appOpenCountFirstRecordedAt != nil)
    }

    @Test("subsequent increments don't overwrite first-recorded-at")
    func preservesFirstRecordedAt() {
        var state: DirectState = makeAppOpenState()
        state.appOpenCount = 0
        state.appOpenCountFirstRecordedAt = nil
        reduceAppOpen(&state, .incrementAppOpenCount)
        let first = state.appOpenCountFirstRecordedAt
        reduceAppOpen(&state, .incrementAppOpenCount)
        reduceAppOpen(&state, .incrementAppOpenCount)
        #expect(state.appOpenCountFirstRecordedAt == first)
    }
}
