//
//  TightControlStreakMiddleware.swift
//  DOSBTS
//
//  U3 (DMNC-772). Observes the glucose stream and the app-active transition, runs the
//  pure TightControlStreakDetector, and routes presentation:
//  - foreground / replay streaks present immediately (deduped by the run-start marker);
//  - background streaks defer into a persisted pending count, drained as one consolidated
//    "×N" toast when the app next becomes active.
//  The middleware is pure: it only emits actions and computes the night-gated feedback
//  flag. All toast/sound/haptic/VoiceOver side effects happen in ContentView's toast
//  controller (U4) at presentation time (R10).
//
//  Trigger separation (race-safety): .addSensorGlucose and .setSensorGlucoseValues both
//  detect-and-present; the run-start marker dedups the double-fire across the async GRDB
//  reload gap. .setAppState(.active) is the SOLE pending-drain trigger, so the drain can
//  never run twice for the same pending count.
//
//  Cross-middleware: .addSensorGlucose is also handled by sensorGlucoseStoreMiddleware
//  (insert + reload), treatmentCycleMiddleware, and glucoseNotificationMiddleware.
//

import Combine
import Foundation

func tightControlStreakMiddleware() -> Middleware<DirectState, DirectAction> {
    return { state, action, _ in
        // R11: the toggle gates the entire feature, including the deferred drain path.
        guard state.showCelebrations else {
            return Empty().eraseToAnyPublisher()
        }

        switch action {
        case .addSensorGlucose(glucoseValues: let glucoseValues):
            // KTD6: the reducer set only `latestSensorGlucose`, NOT `sensorGlucoseValues`,
            // so evaluate against the loaded window PLUS this batch (deduped by timestamp).
            let window = mergeByTimestamp(state.sensorGlucoseValues, glucoseValues)
            return evaluateLiveStreak(window: window, state: state)

        case .setSensorGlucoseValues(glucoseValues: let glucoseValues):
            // Launch replay / post-add reload (only fires while active). The array is
            // authoritative; the marker dedups against the .addSensorGlucose path.
            return evaluateLiveStreak(window: glucoseValues, state: state)

        case .setAppState(appState: let appState):
            // Sole drain trigger — fires on every foreground transition. Present streaks
            // deferred while the app was not active, consolidated as one ×N toast.
            guard appState == .active, state.tightControlPendingCelebrationCount > 0 else {
                break
            }
            let celebration = TightControlCelebration(
                count: state.tightControlPendingCelebrationCount,
                hours: nil,
                withFeedback: tightControlPlaysFeedback(state.activeAlarmProfile)
            )
            return [
                DirectAction.presentTightControlCelebration(celebration: celebration),
                DirectAction.clearTightControlPendingCelebrations
            ].publisher.setFailureType(to: DirectError.self).eraseToAnyPublisher()

        case .setShowCelebrations(enabled: let enabled):
            // AE9: re-enabling consumes the in-progress run (sets the marker to its start)
            // so it can't insta-fire mid-run. No-op when there is no live in-band run.
            guard enabled,
                  let runStart = TightControlStreakDetector.currentRunStart(
                      readings: state.sensorGlucoseValues,
                      now: Date(),
                      config: TightControlConfig.resolved(sensorIntervalMinutes: state.sensorInterval)
                  )
            else {
                break
            }
            return Just(DirectAction.setTightControlLastCelebratedStreakStart(start: runStart))
                .setFailureType(to: DirectError.self)
                .eraseToAnyPublisher()

        default:
            break
        }

        return Empty().eraseToAnyPublisher()
    }
}

// MARK: - Helpers

/// Runs the detector and routes a detected streak: immediate present when active,
/// deferred (count + pending bump) when not.
private func evaluateLiveStreak(window: [SensorGlucose], state: DirectState) -> AnyPublisher<DirectAction, DirectError>? {
    let now = Date()
    let config = TightControlConfig.resolved(sensorIntervalMinutes: state.sensorInterval)
    let result = TightControlStreakDetector.evaluate(
        readings: window,
        lastCelebratedStreakStart: state.tightControlLastCelebratedStreakStart,
        now: now,
        config: config
    )

    guard result.shouldCelebrate, let start = result.celebratedStreakStart else {
        return Empty().eraseToAnyPublisher()
    }

    guard state.appState == .active else {
        // Backgrounded: bump the lifetime count + pending; presented on next active.
        return Just(DirectAction.tightControlStreakCelebrated(streakStart: start, deferred: true))
            .setFailureType(to: DirectError.self)
            .eraseToAnyPublisher()
    }

    let latest = window.map(\.timestamp).max() ?? now
    let hours = Int(latest.timeIntervalSince(start) / 3600)
    let celebration = TightControlCelebration(
        count: 1,
        hours: hours,
        withFeedback: tightControlPlaysFeedback(state.activeAlarmProfile)
    )
    return [
        DirectAction.tightControlStreakCelebrated(streakStart: start, deferred: false),
        DirectAction.presentTightControlCelebration(celebration: celebration)
    ].publisher.setFailureType(to: DirectError.self).eraseToAnyPublisher()
}

/// Dedups `existing + batch` by timestamp, preferring the batch's value for collisions.
private func mergeByTimestamp(_ existing: [SensorGlucose], _ batch: [SensorGlucose]) -> [SensorGlucose] {
    var byTimestamp: [Date: SensorGlucose] = [:]
    for reading in existing { byTimestamp[reading.timestamp] = reading }
    for reading in batch { byTimestamp[reading.timestamp] = reading }
    return Array(byTimestamp.values)
}

/// Sound + haptic accompany the toast unless we're in night-profile hours (R10).
/// Visual + VoiceOver always present; only the audible/tactile channels are gated.
func tightControlPlaysFeedback(_ profile: AlarmProfile) -> Bool {
    profile != .night
}
