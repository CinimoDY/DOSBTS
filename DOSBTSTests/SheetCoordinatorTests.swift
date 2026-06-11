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

@Suite("SheetCoordinator treatment decision")
struct TreatmentPresentDecisionTests {
    @Test("stillLow double-flag fixture yields one present — the recheck — and an empty pending")
    func stillLowDoubleFlagYieldsOneRecheck() {
        // .treatmentCycleStillLow sets recheckDispatched AND
        // showTreatmentPrompt in one reducer transition. Both observers fire
        // against the same state; the decision resolves to the recheck.
        let decision = SheetCoordinator.treatmentPresent(
            showTreatmentPrompt: true,
            alarmFiredAt: Date(),
            recheckDispatched: true,
            treatmentCycleActive: true,
            latestGlucoseValue: 62,
            alarmLow: 80
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
            latestGlucoseValue: 65,
            alarmLow: 80
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
            latestGlucoseValue: 95,
            alarmLow: 80
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
            latestGlucoseValue: 64,
            alarmLow: 80
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
            latestGlucoseValue: nil,
            alarmLow: 80
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
            latestGlucoseValue: nil,
            alarmLow: 80
        )
        #expect(decision == nil)
    }

    @Test("recheck flags set, no glucose, but prompt flag set falls back to the modal")
    func recheckWithoutReadingFallsBackToPrompt() {
        let decision = SheetCoordinator.treatmentPresent(
            showTreatmentPrompt: true,
            alarmFiredAt: Date(),
            recheckDispatched: true,
            treatmentCycleActive: true,
            latestGlucoseValue: nil,
            alarmLow: 80
        )
        #expect(decision?.id == "treatmentModal")
    }
}
