//
//  SheetCoordinatorTests.swift
//  DOSBTSTests
//
//  Pins the single-presentation-root semantics (R8a, AE2a, KTD-1):
//  safety presents preempt and are never queued behind user sheets;
//  ordinary presents pend; duplicates no-op; the stillLow double-flag
//  yields exactly one present.
//

import Foundation
import Testing
@testable import DOSBTSApp

@Suite("SheetCoordinator")
struct SheetCoordinatorTests {
    @Test("present sets activeSheet when idle")
    func presentWhenIdle() {
        let c = SheetCoordinator()
        c.present(.meal)
        #expect(c.activeSheet?.id == "meal")
        #expect(c.pendingSheet == nil)
    }

    @Test("ordinary present while a sheet is up pends")
    func ordinaryPends() {
        let c = SheetCoordinator()
        c.present(.meal)
        c.present(.insulin)
        #expect(c.activeSheet?.id == "meal")
        #expect(c.pendingSheet?.id == "insulin")
    }

    @Test("dismissThenPresent stages and promotes on dismiss")
    func dismissThenPresentPromotes() {
        let c = SheetCoordinator()
        c.present(.treatmentModal(alarmFiredAt: Date()))
        c.dismissThenPresent(.filteredFoodEntry)
        #expect(c.activeSheet == nil)
        #expect(c.pendingSheet?.id == "filteredFoodEntry")

        c.sheetDidDismiss()
        #expect(c.activeSheet?.id == "filteredFoodEntry")
        #expect(c.pendingSheet == nil)
    }

    @Test("safety present while an ordinary sheet is up preempts immediately (AE2a)")
    func safetyPreempts() {
        let c = SheetCoordinator()
        c.present(.meal)
        c.presentSafety(.treatmentModal(alarmFiredAt: Date()))
        // Never queued behind a user sheet — a queued safety prompt a hypo
        // user never sees is the failure mode.
        #expect(c.activeSheet?.id == "treatmentModal")
        #expect(c.pendingSheet == nil)
    }

    @Test("pending collision: ordinary staged, safety requested → ordinary dropped, never the safety")
    func pendingCollisionDropsOrdinary() {
        let c = SheetCoordinator()
        c.present(.meal)
        c.present(.insulin) // staged
        c.presentSafety(.treatmentRecheck(glucoseValue: 62))
        #expect(c.activeSheet?.id == "treatmentRecheck")
        #expect(c.pendingSheet == nil)
    }

    @Test("duplicate present (same id as active) is a no-op")
    func duplicateActiveNoOp() {
        let c = SheetCoordinator()
        c.present(.meal)
        c.present(.meal)
        #expect(c.activeSheet?.id == "meal")
        #expect(c.pendingSheet == nil)
    }

    @Test("duplicate present (same id as pending) is a no-op")
    func duplicatePendingNoOp() {
        let c = SheetCoordinator()
        c.present(.meal)
        c.present(.insulin)
        c.present(.insulin)
        #expect(c.pendingSheet?.id == "insulin")
    }

    @Test("duplicate safety present is a no-op (observer double-fire)")
    func duplicateSafetyNoOp() {
        let c = SheetCoordinator()
        c.presentSafety(.treatmentRecheck(glucoseValue: 60))
        c.presentSafety(.treatmentRecheck(glucoseValue: 60))
        #expect(c.activeSheet?.id == "treatmentRecheck")
        #expect(c.pendingSheet == nil)
    }
}

// MARK: - Treatment decision matrix

/// Fixed clock on a minute boundary — SensorGlucose rounds its timestamp to
/// the minute, so an off-boundary `now` would skew reading ages.
private let fixtureNow = Date(timeIntervalSince1970: 1_800_000_000)

/// A sensor reading `ageMinutes` old relative to `fixtureNow`.
private func reading(_ value: Int, ageMinutes: Int = 0, minuteChange: Double? = nil) -> SensorGlucose {
    SensorGlucose(
        timestamp: fixtureNow.addingTimeInterval(TimeInterval(-ageMinutes * 60)),
        rawGlucoseValue: value,
        intGlucoseValue: value,
        minuteChange: minuteChange
    )
}

@Suite("SheetCoordinator treatment decision")
struct TreatmentPresentDecisionTests {
    @Test("stillLow double-flag fixture yields one present — the recheck — and an empty pending")
    func stillLowDoubleFlagYieldsOneRecheck() {
        // Defensive: .treatmentCycleStillLow no longer sets
        // showTreatmentPrompt (DMNC-1560), but if both flags are ever set
        // together the decision must still resolve to the recheck.
        let decision = SheetCoordinator.treatmentPresent(
            showTreatmentPrompt: true,
            alarmFiredAt: Date(),
            recheckDispatched: true,
            treatmentCycleActive: true,
            latestGlucose: reading(62),
            alarmLow: 80,
            predictive: false,
            now: fixtureNow
        )
        #expect(decision?.id == "treatmentRecheck")

        // Both observers presenting the decision results in ONE sheet:
        let c = SheetCoordinator()
        if let decision { c.presentSafety(decision) }
        if let decision { c.presentSafety(decision) } // second observer
        #expect(c.activeSheet?.id == "treatmentRecheck")
        #expect(c.pendingSheet == nil)
    }

    @Test("plain treatment prompt presents the modal")
    func plainPromptPresentsModal() {
        let decision = SheetCoordinator.treatmentPresent(
            showTreatmentPrompt: true,
            alarmFiredAt: Date(),
            recheckDispatched: false,
            treatmentCycleActive: false,
            latestGlucose: reading(65),
            alarmLow: 80,
            predictive: false,
            now: fixtureNow
        )
        #expect(decision?.id == "treatmentModal")
    }

    @Test("recheck with recovered glucose presents nothing (banner handles STABILISED)")
    func recoveredRecheckPresentsNothing() {
        let decision = SheetCoordinator.treatmentPresent(
            showTreatmentPrompt: false,
            alarmFiredAt: nil,
            recheckDispatched: true,
            treatmentCycleActive: true,
            latestGlucose: reading(95),
            alarmLow: 80,
            predictive: false,
            now: fixtureNow
        )
        #expect(decision == nil)
    }

    @Test("genuine prompt with stale recheck flag from a resolved cycle still presents the modal")
    func stalePromptStillPresents() {
        let decision = SheetCoordinator.treatmentPresent(
            showTreatmentPrompt: true,
            alarmFiredAt: Date(),
            recheckDispatched: true,
            treatmentCycleActive: false, // cycle over — recheck branch can't fire
            latestGlucose: reading(64),
            alarmLow: 80,
            predictive: false,
            now: fixtureNow
        )
        #expect(decision?.id == "treatmentModal")
    }

    @Test("no flags presents nothing")
    func noFlagsNothing() {
        let decision = SheetCoordinator.treatmentPresent(
            showTreatmentPrompt: false,
            alarmFiredAt: nil,
            recheckDispatched: false,
            treatmentCycleActive: false,
            latestGlucose: nil,
            alarmLow: 80,
            predictive: false,
            now: fixtureNow
        )
        #expect(decision == nil)
    }
}

// MARK: - Dismissal-interleaving rows (review follow-up)

@Suite("SheetCoordinator dismissal interleavings")
struct SheetCoordinatorDismissalTests {
    @Test("sheetDidDismiss with nothing staged is a no-op")
    func dismissWithNoPending() {
        let c = SheetCoordinator()
        c.present(.meal)
        c.dismiss()
        c.sheetDidDismiss()
        #expect(c.activeSheet == nil)
        #expect(c.pendingSheet == nil)
    }

    @Test("dismiss() clears the active sheet without touching pending")
    func dismissLeavesPending() {
        let c = SheetCoordinator()
        c.present(.meal)
        c.present(.insulin) // staged
        c.dismiss()
        #expect(c.activeSheet == nil)
        #expect(c.pendingSheet?.id == "insulin")
    }

    @Test("dismissThenPresent overwrites an already-staged sheet — most recent intent wins")
    func dismissThenPresentOverwritesPending() {
        let c = SheetCoordinator()
        c.present(.meal)
        c.present(.insulin) // staged
        c.dismissThenPresent(.filteredFoodEntry)
        #expect(c.activeSheet == nil)
        #expect(c.pendingSheet?.id == "filteredFoodEntry")

        c.sheetDidDismiss()
        #expect(c.activeSheet?.id == "filteredFoodEntry")
        #expect(c.pendingSheet == nil)
    }

    @Test("a present that lands during the dismissal animation wins over the staged sheet")
    func presentDuringDismissalWins() {
        let c = SheetCoordinator()
        c.present(.meal)
        c.dismissThenPresent(.filteredFoodEntry) // staged, dismissal in flight
        c.present(.bloodGlucose) // user acts before onDismiss fires
        #expect(c.activeSheet?.id == "bloodGlucose")

        // onDismiss for the original sheet fires after the new present:
        // the newer present keeps the screen; the staged sheet stays staged.
        c.sheetDidDismiss()
        #expect(c.activeSheet?.id == "bloodGlucose")
        #expect(c.pendingSheet?.id == "filteredFoodEntry")
    }
}

// MARK: - Treatment decision: nil-glucose rows (review follow-up)

extension TreatmentPresentDecisionTests {
    @Test("recheck flags set but no glucose reading presents nothing")
    func recheckWithoutReadingPresentsNothing() {
        let decision = SheetCoordinator.treatmentPresent(
            showTreatmentPrompt: false,
            alarmFiredAt: nil,
            recheckDispatched: true,
            treatmentCycleActive: true,
            latestGlucose: nil,
            alarmLow: 80,
            predictive: false,
            now: fixtureNow
        )
        #expect(decision == nil)
    }

    // MARK: Journal-note prefill (DMNC-1501)

    @Test("a prefilled journal note is the SAME sheet as a bare one — the id is load-bearing")
    func journalNotePrefillKeepsItsIdentity() {
        #expect(ActiveSheet.journalNote(prefill: nil).id == "journalNote")
        #expect(
            ActiveSheet.journalNote(
                prefill: JournalNotePrefill(timestamp: Date(), tag: .stressed)
            ).id == "journalNote"
        )
    }

    @Test("a second journal-note present de-dupes even when it carries a prefill")
    func journalNotePrefillDeDupes() {
        let c = SheetCoordinator()
        c.present(.journalNote(prefill: nil))
        c.present(.journalNote(prefill: JournalNotePrefill(timestamp: Date(), tag: .sick)))
        #expect(c.activeSheet?.id == "journalNote")
        #expect(c.pendingSheet == nil)
    }

    @Test("recheck flags set, no glucose, prompt flag set presents nothing — no evidence of a low (DMNC-1560)")
    func recheckWithoutReadingPromptPresentsNothing() {
        let decision = SheetCoordinator.treatmentPresent(
            showTreatmentPrompt: true,
            alarmFiredAt: Date(),
            recheckDispatched: true,
            treatmentCycleActive: true,
            latestGlucose: nil,
            alarmLow: 80,
            predictive: false,
            now: fixtureNow
        )
        #expect(decision == nil)
    }
}

// MARK: - Treatment decision: prompt currency (DMNC-1560)

/// A prompt set by an alarm that is over (recovered, very stale, no reading)
/// must never present; a genuine low always does.
@Suite("SheetCoordinator treatment decision — prompt currency")
struct TreatmentPromptCurrencyTests {
    private func prompt(
        _ glucose: SensorGlucose?,
        predictive: Bool = false,
        recheckDispatched: Bool = false,
        treatmentCycleActive: Bool = false
    ) -> ActiveSheet? {
        SheetCoordinator.treatmentPresent(
            showTreatmentPrompt: true,
            alarmFiredAt: fixtureNow.addingTimeInterval(-3600),
            recheckDispatched: recheckDispatched,
            treatmentCycleActive: treatmentCycleActive,
            latestGlucose: glucose,
            alarmLow: 80,
            predictive: predictive,
            now: fixtureNow
        )
    }

    @Test("recovered (110) — stale prompt presents nothing")
    func recoveredPresentsNothing() {
        #expect(prompt(reading(110)) == nil)
    }

    @Test("exactly at alarmLow (80) presents nothing")
    func atAlarmLowPresentsNothing() {
        #expect(prompt(reading(80)) == nil)
    }

    @Test("low 62 but 20 min old (very stale) presents nothing")
    func veryStaleLowPresentsNothing() {
        #expect(prompt(reading(62, ageMinutes: 20)) == nil)
    }

    @Test("low 62, 10 min old (amber stale tier) still presents — a BLE gap must not hide a low")
    func staleTierLowPresents() {
        #expect(prompt(reading(62, ageMinutes: 10))?.id == "treatmentModal")
    }

    @Test("fresh low 62 presents the modal")
    func freshLowPresents() {
        #expect(prompt(reading(62))?.id == "treatmentModal")
    }

    @Test("predictive 86 falling 1.0/min (projects to 66) presents the modal")
    func predictiveStillFallingPresents() {
        #expect(prompt(reading(86, minuteChange: -1.0), predictive: true)?.id == "treatmentModal")
    }

    @Test("predictive 86 falling 0.2/min (projects to 82) presents nothing")
    func predictiveFlatteningPresentsNothing() {
        #expect(prompt(reading(86, minuteChange: -0.2), predictive: true) == nil)
    }

    @Test("predictive 91 (outside the alarmLow + 10 zone) presents nothing")
    func predictiveAboveClearZonePresentsNothing() {
        #expect(prompt(reading(91, minuteChange: -3.0), predictive: true) == nil)
    }

    @Test("predictive 86 with no slope presents nothing")
    func predictiveNoSlopePresentsNothing() {
        #expect(prompt(reading(86), predictive: true) == nil)
    }

    @Test("predictive flag but reading 70 (actual low) presents the modal")
    func predictiveFlagActualLowPresents() {
        #expect(prompt(reading(70), predictive: true)?.id == "treatmentModal")
    }

    @Test("stillLow then recovered (all flags set, 110) presents nothing")
    func stillLowThenRecoveredPresentsNothing() {
        #expect(prompt(reading(110), predictive: true, recheckDispatched: true, treatmentCycleActive: true) == nil)
    }

    @Test("recheck branch is not staleness-gated: active cycle + 62 aged 20 presents the recheck")
    func recheckNotStalenessGated() {
        #expect(prompt(reading(62, ageMinutes: 20), recheckDispatched: true, treatmentCycleActive: true)?.id == "treatmentRecheck")
    }
    @Test("predictive prompt uses the smoothed slope when supplied: flat latest reading, falling average still presents")
    func predictiveSmoothedSlopeOverridesLatest() {
        let sheet = SheetCoordinator.treatmentPresent(
            showTreatmentPrompt: true,
            alarmFiredAt: fixtureNow,
            recheckDispatched: false,
            treatmentCycleActive: false,
            latestGlucose: reading(86, minuteChange: -0.1),
            alarmLow: 80,
            predictive: true,
            smoothedMinuteChange: -1.0,
            now: fixtureNow
        )
        #expect(sheet?.id == "treatmentModal")
    }

    @Test("smoothedMinuteChange averages the last three known slopes and needs two samples")
    func smoothedSlopeHelper() {
        let readings = [
            reading(100, ageMinutes: 4, minuteChange: -2.0),
            reading(98, ageMinutes: 3, minuteChange: nil),
            reading(96, ageMinutes: 2, minuteChange: -1.0),
            reading(95, ageMinutes: 1, minuteChange: -0.5),
            reading(94, minuteChange: -1.5),
        ]
        #expect(smoothedMinuteChange(of: readings) == -1.0)
        #expect(smoothedMinuteChange(of: [reading(94, minuteChange: -1.5)]) == nil)
    }
}
