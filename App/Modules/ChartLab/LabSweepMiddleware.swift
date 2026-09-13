//
//  LabSweepMiddleware.swift
//  DOSBTSApp
//
//  Evidence loader for `LAB: SWEEP` (DMNC-1503, Chart Lab P3).
//
//  Data flow:
//    .loadLabSweeps(days:)
//      labSweepMiddleware (guard .active)
//        └─ DataStore.getLabSweepRaw(days:)        ONE asyncRead, no writes
//             → SweepStatistics.build off the main thread
//             → .setLabSweeps(evidence:)
//    LabSweepView renders the sweeps (pure).
//
//  WHY THIS IS NOT THE RATIO LAB'S COLD PATH
//  -----------------------------------------
//  `RatioLabMiddleware` can drop a `.loadRatioEvidence` that arrives while the scene
//  is inactive, because the Ratio Lab is a *pushed* screen — its `onAppear` cannot
//  run before `ContentView` has set `.active`. `.labSweep` is a **persisted report
//  type rendered at the root**: on a cold launch into the sweep tab the view's
//  `onAppear` and the toolbar's day-window normalise can both land while
//  `appState == .inactive`, get dropped, and leave `labSweeps` nil — a loading pulse
//  that never resolves until the user taps a chip. So this middleware owns the
//  trigger set itself, and `.setAppState(.active)` is one of the triggers.
//
//  Triggers, every one of them gated by `reload`'s "the sweep tab is what the user
//  is looking at" guard (a cold path must stay cold for everyone who never opens
//  the lab):
//   • `.setAppState(.active)`      — cold launch into the tab, and every foreground return
//   • `.setSelectedReportType`     — entering the tab (edge-triggered off `lastState`)
//   • `.setStatisticsDays`         — the 7d/30d/90d/ALL chips
//   • `.addMealEntry` / `.updateMealEntry` / `.deleteMealEntry` — the drawn set changed
//   • `.addInsulinDelivery` / `.deleteInsulinDelivery`          — flips `confounded`
//   • `.addExerciseEntry` / `.deleteExerciseEntry`              — flips `confounded`
//   • `.addSensorGlucose`          — ONLY while a sweep is still in progress, so
//                                    today's trace and the LAPS line keep moving
//
//  One known duplicate: `ChartReportTypeRow.normaliseDaysIfNeeded` dispatches
//  `.setStatisticsDays(30)` when the persisted `statisticsDays` is not one of the day
//  chips (it is transient and defaults to 3), so entering the tab in that state costs
//  one extra read — the tab-entry load followed immediately by the normalised one.
//  Correcting it would mean teaching the toolbar about the lab; one extra read on a
//  single transition is the cheaper trade.
//

import Combine
import Foundation

/// Off the main thread for the build: a 90-day set is ~270 meals × 55 grid points,
/// small, but it runs on every chip tap and has no business on the UI thread.
/// One shared serial queue, so two loads cannot interleave.
private let labSweepQueue = DispatchQueue(label: "dosbts.lab-sweep-calculation", qos: .utility)

func labSweepMiddleware() -> Middleware<DirectState, DirectAction> {
    return { state, action, lastState in
        switch action {
        case .loadLabSweeps(days: let days):
            // The guard every DataStore middleware uses. Unlike the Ratio Lab's, a
            // drop here is recoverable: `.setAppState(.active)` below re-asks.
            guard state.appState == .active else {
                break
            }

            let effectiveDays = LabSweepStore.effectiveDays(days)

            // On a GRDB read error the Future emits `.failure`, which the Store logs
            // but never re-dispatches — so `.setLabSweeps` would never land and the
            // view (which treats `labSweeps == nil` as loading) would spin forever.
            // Fall back to an empty evidence set for the window that was asked for:
            // the screen shows its "no meals in the last N days · n=0" state instead.
            return DataStore.shared.getLabSweepRaw(days: effectiveDays)
                .receive(on: labSweepQueue)
                .map { raw -> DirectAction in
                    let sweeps = SweepStatistics.build(
                        meals: raw.meals,
                        readings: raw.readings,
                        deliveries: raw.deliveries,
                        exercise: raw.exercise,
                        now: raw.now
                    )
                    return .setLabSweeps(evidence: LabSweepEvidence(
                        days: raw.days,
                        sweeps: sweeps,
                        loadedAt: raw.now
                    ))
                }
                .catch { error -> Just<DirectAction> in
                    DirectLog.error("Lab sweep load failed: \(error)")
                    return Just(.setLabSweeps(evidence: LabSweepEvidence(
                        days: effectiveDays,
                        sweeps: [],
                        loadedAt: Date()
                    )))
                }
                .setFailureType(to: DirectError.self)
                .eraseToAnyPublisher()

        case .setAppState(appState: let appState):
            // Cold launch into a persisted `.labSweep`, and every return from the
            // background — without this the in-progress trace is frozen at whatever
            // it was when the app went away.
            guard appState == .active else { break }
            return reload(state)

        case .setSelectedReportType:
            // Edge-triggered: only the transition INTO the tab loads. `lastState` is
            // the pre-reducer state (Store.dispatch passes both — State.swift:51).
            guard lastState.selectedReportType != .labSweep else { break }
            return reload(state)

        case .setStatisticsDays:
            // The reducer runs BEFORE middlewares, so `state.statisticsDays` is
            // already the chip the user just tapped.
            return reload(state)

        case .addMealEntry, .updateMealEntry, .deleteMealEntry:
            // Cross-middleware: `.addMealEntry` is also handled by
            // mealEntryStoreMiddleware and favoriteFoodStoreMiddleware. An *update*
            // matters as much as an add here: carbs move the meal between buckets and
            // re-pick its twins, a timestamp moves t=0, a description retitles LAPS.
            return reload(state)

        case .addInsulinDelivery, .deleteInsulinDelivery,
             .addExerciseEntry, .deleteExerciseEntry:
            // A correction bolus or a session overlapping a meal's 2 h window flips
            // that sweep between clean and confounded — which moves the median, the
            // wash, the caption's CLEAN count and the twin set.
            return reload(state)

        case .addSensorGlucose:
            // The headline of this tab is today's unfinished meal. Every new reading
            // extends it — but only while something is actually in progress, so a
            // user parked on the tab overnight does not re-read the period every
            // five minutes for a picture that cannot change.
            guard state.labSweeps?.sweeps.contains(where: \.isInProgress) == true else {
                break
            }
            return reload(state)

        default:
            break
        }

        return Empty().eraseToAnyPublisher()
    }
}

// MARK: - Private

/// Re-ask for the current window, but only while the sweep tab is what the user is
/// actually looking at — the right report type, on the Overview tab, in an active scene.
private func reload(_ state: DirectState) -> AnyPublisher<DirectAction, DirectError>? {
    guard state.selectedReportType == .labSweep,
          state.selectedView == DirectConfig.overviewViewTag,
          state.appState == .active
    else {
        return nil
    }
    return Just(DirectAction.loadLabSweeps(days: state.statisticsDays))
        .setFailureType(to: DirectError.self)
        .eraseToAnyPublisher()
}
