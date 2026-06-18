//
//  TightControlMiddlewareTests.swift
//  DOSBTSTests
//
//  U3 (DMNC-772): the detection middleware's action routing. Verifies the toggle
//  gate (R11/AE7), foreground-immediate vs background-deferred presentation, the
//  consolidated drain (AE5/AE8), night-profile feedback gating (AE6/R10), and
//  re-enable-consumes-run (AE9). The middleware calls Date() internally, so test
//  readings end at the real "now".
//

import Foundation
import Combine
import Testing
@testable import DOSBTSApp

// MARK: - Helpers

private func minutes(_ m: Int) -> TimeInterval { TimeInterval(m * 60) }

/// In-band (or arbitrary-value) readings every 5 min spanning `spanMinutes`, ending at `end`.
private func run(spanMinutes: Int, value: Int = 100, endingAt end: Date) -> [SensorGlucose] {
    var out: [SensorGlucose] = []
    var elapsed = 0
    while elapsed <= spanMinutes {
        out.append(SensorGlucose(timestamp: end.addingTimeInterval(-minutes(elapsed)), rawGlucoseValue: value, intGlucoseValue: value))
        elapsed += 5
    }
    return out
}

private func makeState() -> AppState {
    var state = AppState(defaults: makeTestDefaults())
    state.showCelebrations = true
    state.sensorInterval = 5
    state.appState = .active
    forceDayProfile(&state)
    return state
}

/// Degenerate night window (start == end) → `resolveActiveAlarmProfile` returns `.day` always.
private func forceDayProfile(_ state: inout AppState) {
    state.nightStartHour = 0; state.nightStartMinute = 0
    state.nightEndHour = 0; state.nightEndMinute = 0
}

/// A ±60-minute night window centered on the current minute → `.night` regardless of run time.
private func forceNightProfile(_ state: inout AppState) {
    let comps = Calendar.current.dateComponents([.hour, .minute], from: Date())
    let nowMinute = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    let startMinute = (nowMinute - 60 + 1440) % 1440
    let endMinute = (nowMinute + 60) % 1440
    state.nightStartHour = startMinute / 60; state.nightStartMinute = startMinute % 60
    state.nightEndHour = endMinute / 60; state.nightEndMinute = endMinute % 60
}

private func collect(_ action: DirectAction, _ state: AppState) -> [DirectAction] {
    var emitted: [DirectAction] = []
    let middleware = tightControlStreakMiddleware()
    let cancellable = middleware(state, action, state)?
        .sink(receiveCompletion: { _ in }, receiveValue: { emitted.append($0) })
    cancellable?.cancel()
    return emitted
}

private func celebratedDeferred(_ action: DirectAction) -> Bool? {
    if case .tightControlStreakCelebrated(_, let deferred) = action { return deferred }
    return nil
}

private func presentedCelebration(_ action: DirectAction) -> TightControlCelebration? {
    if case .presentTightControlCelebration(let celebration) = action { return celebration }
    return nil
}

private func isClearPending(_ action: DirectAction) -> Bool {
    if case .clearTightControlPendingCelebrations = action { return true }
    return false
}

private func consumedMarker(_ action: DirectAction) -> Date? {
    if case .setTightControlLastCelebratedStreakStart(let start) = action { return start }
    return nil
}

// MARK: - Tests

@Suite("Tight-control streak middleware (DMNC-772)")
struct TightControlMiddlewareTests {

    // MARK: Toggle gate (R11 / AE7)

    @Test("toggle OFF: a 2h run on .addSensorGlucose emits nothing, and pending is NOT drained")
    func toggleOffGatesEverything() {
        var state = makeState()
        state.showCelebrations = false
        state.tightControlPendingCelebrationCount = 3
        let window = run(spanMinutes: 130, endingAt: Date())

        #expect(collect(.addSensorGlucose(glucoseValues: window), state).isEmpty)
        #expect(collect(.setAppState(appState: .active), state).isEmpty)
    }

    // MARK: Foreground live (R1, R5, R6)

    @Test("foreground live streak emits celebrated(deferred:false) + present(count:1, withFeedback)")
    func foregroundLiveStreakPresents() {
        let state = makeState()
        let window = run(spanMinutes: 130, endingAt: Date())
        let emitted = collect(.addSensorGlucose(glucoseValues: window), state)

        #expect(emitted.count == 2)
        #expect(celebratedDeferred(emitted[0]) == false)
        let celebration = presentedCelebration(emitted[1])
        #expect(celebration?.count == 1)
        #expect(celebration?.hours == 2)
        #expect(celebration?.withFeedback == true)
    }

    // MARK: Background defer (F2)

    @Test("backgrounded streak defers: celebrated(deferred:true), no present")
    func backgroundStreakDefers() {
        var state = makeState()
        state.appState = .background
        let window = run(spanMinutes: 130, endingAt: Date())
        let emitted = collect(.addSensorGlucose(glucoseValues: window), state)

        #expect(emitted.count == 1)
        #expect(celebratedDeferred(emitted[0]) == true)
        #expect(presentedCelebration(emitted[0]) == nil)
    }

    // MARK: Launch replay same-session (KTD7)

    @Test("setSensorGlucoseValues with a new streak while active presents this session")
    func replayStreakPresentsSameSession() {
        let state = makeState()
        let window = run(spanMinutes: 130, endingAt: Date())
        let emitted = collect(.setSensorGlucoseValues(glucoseValues: window), state)

        #expect(emitted.count == 2)
        #expect(celebratedDeferred(emitted[0]) == false)
        #expect(presentedCelebration(emitted[1])?.count == 1)
    }

    // MARK: Night gating (R10 / AE6)

    @Test("AE6: during night-profile hours the present carries withFeedback == false (visual only)")
    func nightProfilePresentsWithoutFeedback() {
        var state = makeState()
        forceNightProfile(&state)
        let window = run(spanMinutes: 130, endingAt: Date())
        let emitted = collect(.addSensorGlucose(glucoseValues: window), state)

        #expect(emitted.count == 2)
        let celebration = presentedCelebration(emitted[1])
        #expect(celebration != nil)            // visual toast still presents
        #expect(celebration?.withFeedback == false)  // but no chime / haptic
    }

    @Test("feedback gating helper: day plays feedback, night does not")
    func feedbackGatingHelper() {
        #expect(tightControlPlaysFeedback(.day) == true)
        #expect(tightControlPlaysFeedback(.night) == false)
    }

    // MARK: Deferred drain (AE5 / AE8)

    @Test("AE8: becoming active drains the pending count as one ×N toast, then clears it")
    func drainPresentsConsolidatedAndClears() {
        var state = makeState()
        state.tightControlPendingCelebrationCount = 2
        let emitted = collect(.setAppState(appState: .active), state)

        #expect(emitted.count == 2)
        let celebration = presentedCelebration(emitted[0])
        #expect(celebration?.count == 2)
        #expect(celebration?.hours == nil)        // consolidated: no hours sub-line
        #expect(celebration?.withFeedback == true)
        #expect(isClearPending(emitted[1]))
    }

    @Test("AE5: a second foreground with nothing pending shows nothing")
    func drainNoOpWhenNothingPending() {
        var state = makeState()
        state.tightControlPendingCelebrationCount = 0
        #expect(collect(.setAppState(appState: .active), state).isEmpty)
    }

    // MARK: Re-enable consumes run (AE9)

    @Test("AE9: re-enabling mid-run consumes the in-progress run (sets the marker, no fire)")
    func reEnableConsumesCurrentRun() {
        let now = Date()
        var state = makeState()
        state.sensorGlucoseValues = run(spanMinutes: 90, endingAt: now) // 90 min in-band, in progress
        let emitted = collect(.setShowCelebrations(enabled: true), state)

        #expect(emitted.count == 1)
        let marker = consumedMarker(emitted[0])
        #expect(marker != nil)
        // The marker is the run's start (~90 min ago), not a celebration.
        if let marker {
            #expect(abs(marker.timeIntervalSince(now.addingTimeInterval(-minutes(90)))) < 60)
        }
    }

    @Test("re-enabling with no in-progress run emits nothing")
    func reEnableNoRunEmitsNothing() {
        var state = makeState()
        state.sensorGlucoseValues = []
        #expect(collect(.setShowCelebrations(enabled: true), state).isEmpty)
    }
}
