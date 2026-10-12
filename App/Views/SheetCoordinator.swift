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

// MARK: - JournalNotePrefill

/// What a surface already knows about the note it is asking for (DMNC-1501).
/// The Chart Lab's residual `?` opens the sheet at the excursion's start; the
/// `STILL <TAG>?` row opens it at now, pre-tagged. Everything else presents
/// with no prefill and the sheet behaves exactly as it always has.
struct JournalNotePrefill {
    let timestamp: Date
    let tag: JournalNoteTag?
}

// MARK: - Active Sheet Enum

enum ActiveSheet: Identifiable {
    case insulin
    case meal
    case bloodGlucose
    /// The prefill is presentation detail, NOT identity — see `id` below.
    case journalNote(prefill: JournalNotePrefill?)
    case treatmentModal(alarmFiredAt: Date)
    case filteredFoodEntry
    case treatmentRecheck(glucoseValue: Int)
    case entryGroupReadOverlay(ConsolidatedMarkerGroup)
    case combinedEntryEdit(ConsolidatedMarkerGroup)
    // What's New auto-sheet (DMNC-1147). Builds are captured at decision time
    // (before lastSeenBuild advances, KTD5); the id is constant so a second
    // present is a no-op.
    case whatsNew(builds: [ChangelogBuild], allBuilds: [ChangelogBuild])

    var id: String {
        switch self {
        case .insulin: return "insulin"
        case .meal: return "meal"
        case .bloodGlucose: return "bloodGlucose"
        // Constant id: the Log tab, the Digest screen and the Chart Lab all
        // present this case, so a second request while it is up is a no-op
        // rather than a duplicate sheet. The prefill deliberately does NOT
        // enter the id — a prefilled present arriving behind a bare one is the
        // same sheet, and racing them would stack two note forms.
        case .journalNote: return "journalNote"
        case .treatmentModal: return "treatmentModal"
        case .filteredFoodEntry: return "filteredFoodEntry"
        case .treatmentRecheck: return "treatmentRecheck"
        case .entryGroupReadOverlay(let g): return "entryGroupReadOverlay-\(g.id)"
        case .combinedEntryEdit(let g): return "combinedEntryEdit-\(g.id)"
        case .whatsNew: return "whatsNew"
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

    /// One derived decision for the treatment observers (and cold launch /
    /// foreground). Pure so the matrix is unit-testable.
    ///
    /// - Recheck: a dispatched still-low recheck of an active cycle with a
    ///   reading below `alarmLow` presents the recheck sheet. Deliberately NOT
    ///   staleness-gated — the cycle owns its own stale-data handling.
    /// - Prompt: `showTreatmentPrompt` + `alarmFiredAt` present the treatment
    ///   modal only while the alarm is still current
    ///   (`isTreatmentPromptCurrent`, DMNC-1560): a fresh-enough reading below
    ///   `alarmLow`, or — for a predictive prompt — one still projected to
    ///   cross it. A prompt surviving recovery, a very stale reading or no
    ///   reading yields nil; the caller clears the flag.
    static func treatmentPresent(
        showTreatmentPrompt: Bool,
        alarmFiredAt: Date?,
        recheckDispatched: Bool,
        treatmentCycleActive: Bool,
        latestGlucose: SensorGlucose?,
        alarmLow: Int,
        predictive: Bool,
        smoothedMinuteChange: Double? = nil,
        now: Date = Date()
    ) -> ActiveSheet? {
        if recheckDispatched, treatmentCycleActive,
           let glucose = latestGlucose?.glucoseValue, glucose < alarmLow {
            return .treatmentRecheck(glucoseValue: glucose)
        }

        // A stale recheckDispatched left over from an earlier, resolved
        // recheck must not block a genuine prompt.
        if showTreatmentPrompt, let alarmFiredAt,
           isTreatmentPromptCurrent(latestGlucose: latestGlucose, alarmLow: alarmLow, predictive: predictive, smoothedMinuteChange: smoothedMinuteChange, now: now) {
            return .treatmentModal(alarmFiredAt: alarmFiredAt)
        }

        return nil
    }

    // MARK: Private

    private func isDuplicate(_ sheet: ActiveSheet) -> Bool {
        sheet.id == activeSheet?.id || sheet.id == pendingSheet?.id
    }
}
