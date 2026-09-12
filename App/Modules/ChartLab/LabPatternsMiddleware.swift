//
//  LabPatternsMiddleware.swift
//  DOSBTSApp
//
//  Chart Lab P4 (DMNC-1503) — on-demand evidence loader for `LAB: PATTERNS`.
//
//  Data flow:
//    LabPatternsView.onAppear → .loadLabPatterns(days:)
//      labPatternsMiddleware (guard .active, days capped at 90)
//        └─ DataStore.getClinicReportData(days:)   ← ONE asyncRead, NO writes
//             → ClinicReportBuilder.hourlyPatterns (off the main actor)
//             → .setLabPatterns(evidence:)
//    LabPatternsView renders PatternBandBuilder / PatternAnalysis (pure)
//
//  Reuses the clinic report's read verbatim: same window, same single read, and
//  `ClinicReportRaw.readings` is exactly what the band and the drill need. A
//  second query shape here would be a second thing to keep correct.
//

import Combine
import Foundation

func labPatternsMiddleware() -> Middleware<DirectState, DirectAction> {
    return { state, action, _ in
        switch action {
        case .loadLabPatterns(days: let days):
            // Same guard every DataStore middleware uses. This load is
            // on-demand from `LabPatternsView.onAppear`, which can only run
            // after ContentView has set `.active`, so there is no
            // `.setAppState(.active)` re-trigger to add.
            guard state.appState == .active else {
                break
            }

            return loadPatterns(days: days)

        case .setStatisticsDays(days: let days):
            // The day chips are shared with TIR / STATISTICS, so the reload is
            // gated on the tab actually being the one that draws a band. The
            // reducer runs BEFORE middlewares, so `state.statisticsDays` is
            // already `days` here — the action's value is used for clarity.
            guard state.appState == .active, state.selectedReportType == .labPatterns else {
                break
            }

            return loadPatterns(days: days)

        default:
            break
        }

        return Empty().eraseToAnyPublisher()
    }
}

// MARK: - Private

/// A TOTAL publisher: a GRDB read error emits `.failure`, which the Store logs
/// but never re-dispatches — so `.setLabPatterns` would never land and the view
/// (which treats `labPatterns == nil` as loading) would spin forever. The
/// fallback is an empty-but-shaped evidence: 24 empty hours, no readings, so
/// the tab shows its honest "collecting" state instead of a permanent pulse.
private func loadPatterns(days: Int) -> AnyPublisher<DirectAction, DirectError> {
    let capped = LabPatternEvidence.cappedDays(days)

    return DataStore.shared.getClinicReportData(days: capped)
        .map { raw in
            DirectAction.setLabPatterns(evidence: LabPatternEvidence(
                days: capped,
                hourly: ClinicReportBuilder.hourlyPatterns(from: raw.readings),
                readings: raw.readings,
                period: raw.period
            ))
        }
        .catch { error -> Just<DirectAction> in
            DirectLog.error("Lab patterns evidence load failed: \(error)")
            let now = Date()
            return Just(.setLabPatterns(evidence: LabPatternEvidence(
                days: capped,
                hourly: ClinicReportBuilder.hourlyPatterns(from: []),
                readings: [],
                period: DateInterval(start: now.addingTimeInterval(-Double(capped) * 24 * 3600), end: now)
            )))
        }
        .setFailureType(to: DirectError.self)
        .eraseToAnyPublisher()
}
