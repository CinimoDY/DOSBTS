//
//  TightControlReducerTests.swift
//  DOSBTSTests
//
//  U1 (DMNC-772): persisted state + reducer for the tight-control streak
//  celebration. Covers the four persisted properties, the reducer mutations,
//  fresh-store defaults, and persistence across a re-init with the same
//  injected UserDefaults suite. AE8 (count rises by N) state is covered here;
//  the detection idempotency / presentation facets live in U2/U3 tests.
//

import Foundation
import Testing
@testable import DOSBTSApp

private func makeCelebrationState() -> AppState {
    AppState(defaults: makeTestDefaults())
}

private func reduce(_ state: inout DirectState, _ action: DirectAction) {
    directReducer(state: &state, action: action)
}

@Suite("Tight-control celebration reducer (DMNC-772)")
struct TightControlReducerTests {

    // MARK: Defaults

    @Test("fresh state defaults: celebrations on, count 0, marker nil, pending 0")
    func freshDefaults() {
        let state = makeCelebrationState()
        #expect(state.showCelebrations == true)
        #expect(state.tightControlStreakCount == 0)
        #expect(state.tightControlLastCelebratedStreakStart == nil)
        #expect(state.tightControlPendingCelebrationCount == 0)
    }

    @Test("values persist across a re-init with the same injected defaults")
    func valuesSurviveReinit() {
        let defaults = makeTestDefaults()
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        var writer = AppState(defaults: defaults)
        writer.showCelebrations = false
        writer.tightControlStreakCount = 4
        writer.tightControlLastCelebratedStreakStart = start
        writer.tightControlPendingCelebrationCount = 2

        let reloaded = AppState(defaults: defaults)
        #expect(reloaded.showCelebrations == false)
        #expect(reloaded.tightControlStreakCount == 4)
        #expect(reloaded.tightControlLastCelebratedStreakStart == start)
        #expect(reloaded.tightControlPendingCelebrationCount == 2)
    }

    // MARK: setShowCelebrations

    @Test("setShowCelebrations toggles the flag both ways")
    func togglesFlag() {
        var state: DirectState = makeCelebrationState()
        reduce(&state, .setShowCelebrations(enabled: false))
        #expect(state.showCelebrations == false)
        reduce(&state, .setShowCelebrations(enabled: true))
        #expect(state.showCelebrations == true)
    }

    // MARK: tightControlStreakCelebrated

    @Test("celebrated (immediate) increments the count by one and stores the marker")
    func celebratedImmediate() {
        var state: DirectState = makeCelebrationState()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        reduce(&state, .tightControlStreakCelebrated(streakStart: start, deferred: false))
        #expect(state.tightControlStreakCount == 1)
        #expect(state.tightControlLastCelebratedStreakStart == start)
        #expect(state.tightControlPendingCelebrationCount == 0)
    }

    @Test("celebrated (deferred) bumps both the lifetime count and the pending ×N count — AE8")
    func celebratedDeferred() {
        var state: DirectState = makeCelebrationState()
        let first = Date(timeIntervalSince1970: 1_700_000_000)
        let second = Date(timeIntervalSince1970: 1_700_010_000)
        reduce(&state, .tightControlStreakCelebrated(streakStart: first, deferred: true))
        reduce(&state, .tightControlStreakCelebrated(streakStart: second, deferred: true))
        #expect(state.tightControlStreakCount == 2)
        #expect(state.tightControlPendingCelebrationCount == 2)
        #expect(state.tightControlLastCelebratedStreakStart == second)
    }

    // MARK: setTightControlLastCelebratedStreakStart (consume current run on re-enable, AE9)

    @Test("marker-only setter updates the dedup marker without touching the count")
    func consumeRunSetsMarkerOnly() {
        var state: DirectState = makeCelebrationState()
        state.tightControlStreakCount = 3
        let runStart = Date(timeIntervalSince1970: 1_700_020_000)
        reduce(&state, .setTightControlLastCelebratedStreakStart(start: runStart))
        #expect(state.tightControlLastCelebratedStreakStart == runStart)
        #expect(state.tightControlStreakCount == 3)
    }

    // MARK: clearTightControlPendingCelebrations (drain after presenting)

    @Test("clearing pending resets it to zero while leaving the lifetime count intact")
    func clearPending() {
        var state: DirectState = makeCelebrationState()
        reduce(&state, .tightControlStreakCelebrated(streakStart: Date(timeIntervalSince1970: 1_700_000_000), deferred: true))
        reduce(&state, .clearTightControlPendingCelebrations)
        #expect(state.tightControlPendingCelebrationCount == 0)
        #expect(state.tightControlStreakCount == 1)
    }
}
