//
//  LabWindowMiddleware.swift
//  DOSBTSApp
//
//  Chart Lab P1 (DMNC-1506) — the whole-system window loader.
//
//  Data flow:
//    LabNightView.onAppear → .loadLabWindow(interval:streams:)
//      labWindowMiddleware (guard .active)
//        ├─ DataStore.getLabWindowRaw(interval:)        — ONE asyncRead
//        ├─ LabHealthKitService.fetchSleep(in:)         — its own .catch
//        └─ LabHealthKitService.fetchHourlyHeartRate(in:)
//             → LabWindowSnapshot.assemble (pure)
//             → .setLabWindow(snapshot:)
//
//  Every leg is total. Each HealthKit read carries its own `.catch` so one
//  denial or one throw can never sink the window, and the whole publisher has a
//  final `.catch` → an empty snapshot, because `.setLabWindow` never landing
//  would leave the view treating `labWindow == nil` as "still loading" forever
//  (middleware-failure-swallowed-nil-as-loading-spins-20260704).
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
            // Same guard every DataStore middleware uses: a load dispatched
            // while the scene is inactive races the ContentView.onAppear that
            // sets `.active`.
            guard state.appState == .active else {
                break
            }

            return loadWindow(
                interval: interval,
                streams: streams,
                state: state,
                service: service
            )

        case .setSelectedDate:
            // The day pager moves the NIGHT window by a day. Only the tab that
            // uses the window reloads it — no other surface pays for this read.
            guard state.selectedReportType == .labNight else {
                break
            }

            let interval = NightWindow.interval(for: state.selectedDate ?? Date())
            return Just(DirectAction.loadLabWindow(interval: interval, streams: LabNightStreams.all))
                .setFailureType(to: DirectError.self)
                .eraseToAnyPublisher()

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

    let sleep = healthKitLeg(
        wanted: streams.contains(.sleep),
        service: service,
        mayPrompt: mayPrompt,
        availability: { $0.sleepAvailability },
        fetch: { try await $0.fetchSleep(in: interval) },
        label: "sleep"
    )

    let heartRate = healthKitLeg(
        wanted: streams.contains(.heartRate),
        service: service,
        mayPrompt: mayPrompt,
        availability: { $0.heartRateAvailability },
        fetch: { try await $0.fetchHourlyHeartRate(in: interval) },
        label: "heart rate"
    )

    return Publishers.Zip3(grdb, sleep, heartRate)
        .map { raw, sleepLeg, heartRateLeg in
            DirectAction.setLabWindow(snapshot: LabWindowSnapshot.assemble(
                raw: raw,
                interval: interval,
                heartRate: heartRateLeg.samples,
                sleep: sleepLeg.samples,
                heartRateAvailability: heartRateLeg.availability,
                sleepAvailability: sleepLeg.availability
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

// MARK: - HealthKit leg

/// One HealthKit stream's rows plus what we are allowed to say about them.
private struct LabHealthKitLeg<Sample> {
    let samples: [Sample]
    let availability: LabStreamAvailability
}

/// A HealthKit read that can never fail the zip: a throw becomes `.failed`, a
/// never-asked type becomes `.unavailable`, and either way the window still
/// lands with its GRDB streams intact.
private func healthKitLeg<Sample>(
    wanted: Bool,
    service: LazyService<LabHealthKitService>,
    mayPrompt: Bool,
    availability: @escaping (LabHealthKitService) -> LabStreamAvailability,
    fetch: @escaping (LabHealthKitService) async throws -> [Sample],
    label: String
) -> AnyPublisher<LabHealthKitLeg<Sample>, DirectError> {
    guard wanted else {
        return Just(LabHealthKitLeg<Sample>(samples: [], availability: .unavailable))
            .setFailureType(to: DirectError.self)
            .eraseToAnyPublisher()
    }

    return Future<LabHealthKitLeg<Sample>, DirectError> { promise in
        Task {
            let health = service.value

            if mayPrompt {
                await health.requestAccessIfNeeded()
            }

            let status = availability(health)
            guard status == .available else {
                promise(.success(LabHealthKitLeg(samples: [], availability: status)))
                return
            }

            do {
                let samples = try await fetch(health)
                promise(.success(LabHealthKitLeg(samples: samples, availability: .available)))
            } catch {
                DirectLog.error("Chart Lab \(label) read failed: \(error.localizedDescription)")
                promise(.success(LabHealthKitLeg(samples: [], availability: .failed)))
            }
        }
    }
    .eraseToAnyPublisher()
}
