//
//  LabWindowMiddleware.swift
//  DOSBTSApp
//
//  Chart Lab P1 (DMNC-1506) — the whole-system window loader.
//
//  Data flow:
//    LabNightView (onAppear / selectedDate / scene active) → .loadLabWindow
//      labWindowMiddleware (guard .active)
//        ├─ DataStore.getLabWindowRaw(interval:)        — ONE asyncRead
//        └─ ONE HealthKit Task: authorize once, then sleep + heart rate
//             → LabWindowSnapshot.assemble (pure)
//             → .setLabWindow(snapshot:)
//
//  Every leg is total. The HealthKit reads can only ever downgrade their OWN
//  stream's status, so a denial or a throw never sinks the window, and the whole
//  publisher has a final `.catch` → an empty snapshot, because `.setLabWindow`
//  never landing would leave the view treating `labWindow == nil` as "still
//  loading" forever (middleware-failure-swallowed-nil-as-loading-spins-20260704).
//
//  Triggers are deliberately NOT here. They live in `LabNightView`, so the read
//  — and the HealthKit consent dialog that can come with it — happens only while
//  the tab that needs the window is actually on screen.
//

import Combine
import Foundation

func labWindowMiddleware() -> Middleware<DirectState, DirectAction> {
    labWindowMiddleware(service: LazyService<LabHealthKitService>(initialization: {
        LabHealthKitService()
    }))
}

private func labWindowMiddleware(service: LazyService<LabHealthKitService>) -> Middleware<DirectState, DirectAction> {
    return { state, action, _ in
        switch action {
        case .loadLabWindow(interval: let interval, streams: let streams):
            // Same guard every DataStore middleware uses. The view re-arms the
            // load on `.setAppState(.active)`, so a load dispatched during a
            // cold launch — before ContentView sets `.active` — is retried
            // rather than silently dropped into a permanent loading state.
            guard state.appState == .active else {
                break
            }

            return loadWindow(
                interval: interval,
                streams: streams,
                state: state,
                service: service
            )

        default:
            break
        }

        return Empty().eraseToAnyPublisher()
    }
}

// MARK: - LabNightStreams

/// What `LAB: NIGHT` asks the loader for. Steps are deliberately absent — this
/// build does not read them, and the POST strip says so.
enum LabNightStreams {
    static let all: Set<LabStream> = [
        .glucose, .bloodGlucose, .meals, .insulin, .iob, .exercise, .heartRate, .sleep, .journalNotes,
    ]
}

// MARK: - Load

private func loadWindow(
    interval: DateInterval,
    streams: Set<LabStream>,
    state: DirectState,
    service: LazyService<LabHealthKitService>
) -> AnyPublisher<DirectAction, DirectError> {
    let iobLookbackMinutes = max(state.bolusInsulinPreset.diaMinutes, state.basalDIAMinutes)
    // The lab completes a consent the user already gave; it never opens a new
    // one. With Apple Health import off we read what we are already allowed to
    // read and report `n/a` for the rest.
    let mayPrompt = state.appleHealthImport

    let grdb = DataStore.shared.getLabWindowRaw(
        interval: interval,
        iobLookbackMinutes: iobLookbackMinutes
    )

    let healthKit = healthKitLegs(
        interval: interval,
        wantsSleep: streams.contains(.sleep),
        wantsHeartRate: streams.contains(.heartRate),
        mayPrompt: mayPrompt,
        service: service
    )

    return Publishers.Zip(grdb, healthKit)
        .map { raw, legs in
            DirectAction.setLabWindow(snapshot: LabWindowSnapshot.assemble(
                raw: raw,
                interval: interval,
                heartRate: legs.heartRate.samples,
                sleep: legs.sleep.samples,
                heartRateAvailability: legs.heartRate.availability,
                sleepAvailability: legs.sleep.availability
            ))
        }
        .catch { error -> Just<DirectAction> in
            DirectLog.error("Lab window load failed: \(error)")
            // NOT nil: the view reads `labWindow == nil` as "still loading", so
            // a failure that emitted nothing would spin forever.
            return Just(.setLabWindow(snapshot: .empty(interval: interval, status: .failed)))
        }
        .setFailureType(to: DirectError.self)
        .eraseToAnyPublisher()
}

// MARK: - HealthKit legs

/// One HealthKit stream's rows plus what we are allowed to say about them.
private struct LabHealthKitLeg<Sample> {
    let samples: [Sample]
    let availability: LabStreamAvailability

    static var unavailable: LabHealthKitLeg { LabHealthKitLeg(samples: [], availability: .unavailable) }
}

private struct LabHealthKitLegs {
    let sleep: LabHealthKitLeg<SleepSample>
    let heartRate: LabHealthKitLeg<HeartRateSample>
}

/// Both HealthKit reads in ONE Task, behind ONE authorization step.
///
/// They used to be two independent `Future`s that each awaited
/// `requestAccessIfNeeded()`, which meant a user with Apple Health import on and
/// sleep still `.notDetermined` got TWO overlapping system prompts for the same
/// type. Authorization is asked once, up front; the reads follow.
///
/// Never fails: a throw becomes `.failed` for that stream alone, a never-asked
/// type becomes `.unavailable`, and the window still lands with its GRDB
/// streams intact either way.
private func healthKitLegs(
    interval: DateInterval,
    wantsSleep: Bool,
    wantsHeartRate: Bool,
    mayPrompt: Bool,
    service: LazyService<LabHealthKitService>
) -> AnyPublisher<LabHealthKitLegs, DirectError> {
    guard wantsSleep || wantsHeartRate else {
        return Just(LabHealthKitLegs(sleep: .unavailable, heartRate: .unavailable))
            .setFailureType(to: DirectError.self)
            .eraseToAnyPublisher()
    }

    return Future<LabHealthKitLegs, DirectError> { promise in
        Task {
            let health = service.value

            // ONCE, before either read.
            if mayPrompt {
                await health.requestAccessIfNeeded()
            }

            async let sleep = leg(
                wanted: wantsSleep,
                availability: health.sleepAvailability,
                label: "sleep"
            ) { try await health.fetchSleep(in: interval) }

            async let heartRate = leg(
                wanted: wantsHeartRate,
                availability: health.heartRateAvailability,
                label: "heart rate"
            ) { try await health.fetchHourlyHeartRate(in: interval) }

            promise(.success(LabHealthKitLegs(sleep: await sleep, heartRate: await heartRate)))
        }
    }
    .eraseToAnyPublisher()
}

private func leg<Sample>(
    wanted: Bool,
    availability: LabStreamAvailability,
    label: String,
    fetch: () async throws -> [Sample]
) async -> LabHealthKitLeg<Sample> {
    guard wanted else { return .unavailable }
    guard availability == .available else {
        return LabHealthKitLeg(samples: [], availability: availability)
    }

    do {
        return LabHealthKitLeg(samples: try await fetch(), availability: .available)
    } catch {
        DirectLog.error("Chart Lab \(label) read failed: \(error.localizedDescription)")
        return LabHealthKitLeg(samples: [], availability: .failed)
    }
}
