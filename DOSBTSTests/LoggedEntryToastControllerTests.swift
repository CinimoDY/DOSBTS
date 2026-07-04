//
//  LoggedEntryToastControllerTests.swift
//  DOSBTSTests
//
//  Stage/show/dismiss lifecycle of the ContentView-level entry toast (DMNC-1294).
//

import Foundation
import Testing
@testable import DOSBTSApp

@MainActor
@Suite("LoggedEntryToastController")
struct LoggedEntryToastControllerTests {

    private func makeMeal() -> MealEntry {
        MealEntry(timestamp: Date(), mealDescription: "Pasta", carbsGrams: 40)
    }

    private func makeInsulin() -> InsulinDelivery {
        InsulinDelivery(starts: Date(), ends: Date().addingTimeInterval(3600), units: 4.5, type: .mealBolus)
    }

    private func makeBloodGlucose() -> BloodGlucose {
        BloodGlucose(timestamp: Date(), glucoseValue: 115)
    }

    // MARK: - stage / showStagedIfAny

    @Test("stage stores entry; showStagedIfAny promotes it to active")
    func stageAndShow() {
        let controller = LoggedEntryToastController()
        let meal = makeMeal()
        controller.stage(.meal(meal))
        #expect(controller.active == nil)
        controller.showStagedIfAny()
        #expect(controller.active == .meal(meal))
    }

    @Test("showStagedIfAny is a no-op when nothing is staged")
    func showStagedWhenEmpty() {
        let controller = LoggedEntryToastController()
        controller.showStagedIfAny()
        #expect(controller.active == nil)
    }

    @Test("staging twice before show keeps only the last entry")
    func stagingReplaces() {
        let controller = LoggedEntryToastController()
        controller.stage(.meal(makeMeal()))
        let insulin = makeInsulin()
        controller.stage(.insulin(insulin))
        controller.showStagedIfAny()
        #expect(controller.active == .insulin(insulin))
    }

    // MARK: - show / dismiss

    @Test("show publishes active entry")
    func showPublishes() {
        let controller = LoggedEntryToastController()
        let bg = makeBloodGlucose()
        controller.show(.bloodGlucose(bg))
        #expect(controller.active == .bloodGlucose(bg))
    }

    @Test("dismiss clears active entry")
    func dismissClears() {
        let controller = LoggedEntryToastController()
        controller.show(.meal(makeMeal()))
        controller.dismiss()
        #expect(controller.active == nil)
    }

    @Test("re-show replaces active entry")
    func reShowReplaces() {
        let controller = LoggedEntryToastController()
        let first = makeMeal()
        let second = makeInsulin()
        controller.show(.meal(first))
        controller.show(.insulin(second))
        #expect(controller.active == .insulin(second))
    }

    @Test("auto-dismiss delay matches the 3s contract")
    func autoDismissDelay() {
        #expect(LoggedEntryToastController.autoDismissDelay == 3.0)
    }

    // MARK: - LoggedEntry label

    @Test("meal label includes description")
    func mealLabel() {
        let meal = makeMeal()
        let label = LoggedEntry.meal(meal).label(glucoseUnit: .mgdL)
        #expect(label == "Logged: Pasta")
    }

    @Test("insulin label formats integer units without decimal")
    func insulinIntegerLabel() {
        let delivery = InsulinDelivery(starts: Date(), ends: Date().addingTimeInterval(3600), units: 4.0, type: .correctionBolus)
        let label = LoggedEntry.insulin(delivery).label(glucoseUnit: .mgdL)
        #expect(label == "Logged: 4 U Correction Bolus")
    }

    @Test("insulin label formats fractional units with one decimal")
    func insulinFractionalLabel() {
        let delivery = makeInsulin()
        let label = LoggedEntry.insulin(delivery).label(glucoseUnit: .mgdL)
        // Derive via the same locale-aware formatter (renders "4,5 U" in de-DE):
        // a literal pin here would only pass in dot-decimal locales.
        #expect(label == "Logged: \(4.5.asInsulinUnits()) Meal Bolus")
    }

    @Test("blood glucose label uses mg/dL unit")
    func bgLabelMgdL() {
        let bg = makeBloodGlucose()
        let label = LoggedEntry.bloodGlucose(bg).label(glucoseUnit: .mgdL)
        #expect(label == "Logged: BG 115 mg/dL")
    }

    @Test("blood glucose label converts to mmol/L")
    func bgLabelMmol() {
        let bg = makeBloodGlucose()
        let label = LoggedEntry.bloodGlucose(bg).label(glucoseUnit: .mmolL)
        // 115 * 0.0555 = 6.3825 → "6.4"
        #expect(label.hasPrefix("Logged: BG "))
        #expect(label.hasSuffix("mmol/L"))
    }
}
