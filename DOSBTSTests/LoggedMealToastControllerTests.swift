//
//  LoggedMealToastControllerTests.swift
//  DOSBTSTests
//
//  Show/dismiss/re-show lifecycle of the shared toast controller (DMNC-796).
//

import Foundation
import Testing
@testable import DOSBTSApp

@MainActor
@Suite("LoggedMealToastController")
struct LoggedMealToastControllerTests {

    private func makeMeal(_ description: String) -> MealEntry {
        MealEntry(timestamp: Date(), mealDescription: description, carbsGrams: 10)
    }

    @Test("show publishes the passed entry")
    func showPublishes() {
        let controller = LoggedMealToastController()
        let meal = makeMeal("Pasta")
        controller.show(meal)
        #expect(controller.meal?.id == meal.id)
    }

    @Test("dismiss clears the entry")
    func dismissClears() {
        let controller = LoggedMealToastController()
        controller.show(makeMeal("Pasta"))
        controller.dismiss()
        #expect(controller.meal == nil)
    }

    @Test("re-show before auto-dismiss replaces the entry")
    func reShowReplaces() {
        // Covers the workItem.cancel() + reassign path: the second entry must
        // be the visible one and the first must not linger.
        let controller = LoggedMealToastController()
        let first = makeMeal("First")
        let second = makeMeal("Second")
        controller.show(first)
        controller.show(second)
        #expect(controller.meal?.id == second.id)
    }

    @Test("auto-dismiss delay matches the shipped 3s contract")
    func autoDismissDelay() {
        #expect(LoggedMealToastController.autoDismissDelay == 3.0)
    }
}
