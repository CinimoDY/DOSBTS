//
//  LabSweepMiddleware.swift
//  DOSBTSApp
//
//  On-demand evidence loader for `LAB: SWEEP` (DMNC-1503, Chart Lab P3), built on
//  the Ratio Lab's cold-path template (`RatioLabMiddleware.swift:21-53`).
//
//  Data flow:
//    LabSweepView.onAppear → .loadLabSweeps(days:)
//      labSweepMiddleware (guard .active)
//        └─ DataStore.getLabSweepRaw(days:)        ONE asyncRead, no writes
//             → SweepStatistics.build off the main thread
//             → .setLabSweeps(evidence:)
//    LabSweepView renders the sweeps (pure).
//
//  Re-triggers, all of them only while the sweep tab is the selected report type
//  (a cold path must stay cold for every user who never opens the lab):
//   • `.setStatisticsDays`  — the 7d/30d/90d/ALL chips
//   • `.addMealEntry` / `.deleteMealEntry` — the set the tab is drawing changed
//

import Combine
import Foundation

/// Off the main thread for the build: a 90-day set is ~360 meals × 55 grid points,
/// small, but it runs on every chip tap and has no business on the UI thread.
/// One shared serial queue, so two loads cannot interleave.
private let labSweepQueue = DispatchQueue(label: "dosbts.lab-sweep-calculation", qos: .utility)

func labSweepMiddleware() -> Middleware<DirectState, DirectAction> {
    return { state, action, _ in
        switch action {
        case .loadLabSweeps(days: let days):
            // Same guard every DataStore middleware uses. No `.setAppState(.active)`
            // re-trigger: this load is on-demand from `LabSweepView.onAppear`, which
            // can only run after ContentView has set `.active`.
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

        case .setStatisticsDays:
            // The reducer runs BEFORE middlewares, so `state.statisticsDays` is
            // already the chip the user just tapped.
            return reload(state)

        case .addMealEntry, .deleteMealEntry:
            // Cross-middleware: `.addMealEntry` is also handled by
            // mealEntryStoreMiddleware and favoriteFoodStoreMiddleware. This arm
            // only refreshes what the sweep tab is drawing, and only while it is
            // on screen.
            return reload(state)

        default:
            break
        }

        return Empty().eraseToAnyPublisher()
    }
}

// MARK: - Private

/// Re-ask for the current window, but only while the sweep tab is what the user is
/// looking at.
private func reload(_ state: DirectState) -> AnyPublisher<DirectAction, DirectError>? {
    guard state.selectedReportType == .labSweep, state.appState == .active else {
        return nil
    }
    return Just(DirectAction.loadLabSweeps(days: state.statisticsDays))
        .setFailureType(to: DirectError.self)
        .eraseToAnyPublisher()
}
