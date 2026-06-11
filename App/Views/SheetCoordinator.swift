//
//  SheetCoordinator.swift
//  DOSBTS
//
//  Single app-level presentation root (R8a). The ActiveSheet enum,
//  pendingSheet sequencing, and treatment-prompt/recheck observers moved
//  here from OverviewView so any surface (chart taps, quick actions, the
//  persistent status bar, treatment observers) presents through ONE root —
//  a second root recreates the sibling-sheet collision class
//  (docs/solutions/ui-bugs/swiftui-nested-sheets-present-wrong-view-20260316.md).
//

import Combine
import Foundation

// MARK: - Active Sheet Enum

enum ActiveSheet: Identifiable {
    case insulin
    case meal
    case bloodGlucose
    case treatmentModal(alarmFiredAt: Date)
    case filteredFoodEntry
    case treatmentRecheck(glucoseValue: Int)
    case entryGroupReadOverlay(ConsolidatedMarkerGroup)
    case combinedEntryEdit(ConsolidatedMarkerGroup)

    var id: String {
        switch self {
        case .insulin: return "insulin"
        case .meal: return "meal"
        case .bloodGlucose: return "bloodGlucose"
        case .treatmentModal: return "treatmentModal"
        case .filteredFoodEntry: return "filteredFoodEntry"
        case .treatmentRecheck: return "treatmentRecheck"
        case .entryGroupReadOverlay(let g): return "entryGroupReadOverlay-\(g.id)"
        case .combinedEntryEdit(let g): return "combinedEntryEdit-\(g.id)"
        }
    }
}

// MARK: - SheetCoordinator

/// Present semantics (KTD-1):
/// - *Safety presents* (`treatmentModal`, `treatmentRecheck`) **preempt** —
///   they replace the active sheet immediately, matching the pre-lift
///   observer behavior where the treatment modal swapped in over anything.
///   A queued safety prompt a hypo user never sees is the failure mode.
/// - *Ordinary presents* follow the pendingSheet path: present directly when
///   nothing is up, otherwise stage behind the active sheet.
/// - Contention: at most one pending sheet; safety always survives a
///   collision (a staged ordinary is dropped when safety preempts).
/// - Duplicate present requests (same case id as active or pending) are
///   ignored — this is also what collapses the stillLow double-flag into
///   exactly one visible present.
final class SheetCoordinator: ObservableObject {
    @Published var activeSheet: ActiveSheet?
    @Published private(set) var pendingSheet: ActiveSheet?

    // MARK: Present

    /// Ordinary present: direct when idle, staged when a sheet is up.
    func present(_ sheet: ActiveSheet) {
        guard !isDuplicate(sheet) else { return }

        if activeSheet == nil {
            activeSheet = sheet
        } else {
            // Most-recent intent wins the single pending slot.
            pendingSheet = sheet
        }
    }

    /// Safety present: preempts immediately. Never queued — a staged
    /// ordinary sheet is dropped, never the safety.
    func presentSafety(_ sheet: ActiveSheet) {
        guard !isDuplicate(sheet) else { return }

        pendingSheet = nil
        activeSheet = sheet
    }

    /// Dismiss-then-present sequencing (e.g. treatment modal → filtered
    /// food entry): stages the next sheet and closes the current one; the
    /// onDismiss hook promotes it once the dismissal animation completes.
    func dismissThenPresent(_ sheet: ActiveSheet) {
        pendingSheet = sheet
        activeSheet = nil
    }

    func dismiss() {
        activeSheet = nil
    }

    /// Wire to `.sheet(item:onDismiss:)` — promotes a staged sheet.
    func sheetDidDismiss() {
        // A present that landed during the dismissal animation wins; the
        // staged sheet stays staged and promotes when that one dismisses.
        guard activeSheet == nil else { return }

        if let pending = pendingSheet {
            pendingSheet = nil
            activeSheet = pending
        }
    }

    // MARK: Treatment decision

    /// One derived decision for the treatment observers (and cold launch):
    /// `.treatmentCycleStillLow` sets `recheckDispatched` AND
    /// `showTreatmentPrompt` in a single reducer transition; both onChange
    /// observers fire against the same new state and must yield exactly one
    /// present — the recheck wins. Pure so the matrix is unit-testable.
    static func treatmentPresent(
        showTreatmentPrompt: Bool,
        alarmFiredAt: Date?,
        recheckDispatched: Bool,
        treatmentCycleActive: Bool,
        latestGlucoseValue: Int?,
        alarmLow: Int
    ) -> ActiveSheet? {
        // Recheck takes priority over the prompt when both flags are set.
        if recheckDispatched, treatmentCycleActive,
           let glucose = latestGlucoseValue, glucose < alarmLow {
            return .treatmentRecheck(glucoseValue: glucose)
        }

        // The stillLow double-flag write always satisfies the recheck branch
        // above (cycle active, glucose below low), so reaching here with a
        // prompt flag means a genuine prompt — present it even if a stale
        // recheckDispatched is still set from an earlier, resolved recheck.
        if showTreatmentPrompt, let alarmFiredAt {
            return .treatmentModal(alarmFiredAt: alarmFiredAt)
        }

        return nil
    }

    // MARK: Private

    private func isDuplicate(_ sheet: ActiveSheet) -> Bool {
        sheet.id == activeSheet?.id || sheet.id == pendingSheet?.id
    }
}
