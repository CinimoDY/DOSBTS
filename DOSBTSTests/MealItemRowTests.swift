//
//  MealItemRowTests.swift
//  DOSBTSTests
//
//  Pins the MealItemRow display model (R3/AE4): per-variant content
//  mapping, carbs label presence, and the no-clipping guarantee
//  (truncation is a rendering concern; the model keeps the full name).
//

import Foundation
import Testing
@testable import DOSBTSApp

@Suite("MealItemRow display model")
struct MealItemRowTests {
    private func makeMeal(
        description: String = "Scrambled eggs",
        carbs: Double? = 25,
        protein: Double? = nil,
        fat: Double? = nil,
        calories: Double? = nil
    ) -> MealEntry {
        MealEntry(
            timestamp: Date(timeIntervalSince1970: 1_750_000_000),
            mealDescription: description,
            carbsGrams: carbs,
            proteinGrams: protein,
            fatGrams: fat,
            calories: calories
        )
    }

    @Test("recent variant renders name and carbs, no timestamp or macros")
    func recentVariant() {
        let model = MealItemDisplayModel(meal: makeMeal(), variant: .recent)
        #expect(model.name == "Scrambled eggs")
        #expect(model.carbsLabel == "25g carbs")
        #expect(model.timestampLabel == nil)
        #expect(model.macroLabels.isEmpty)
    }

    @Test("carbs label omitted when meal has no carbs")
    func carbsOmittedWhenNil() {
        let recent = MealItemDisplayModel(meal: makeMeal(carbs: nil), variant: .recent)
        #expect(recent.carbsLabel == nil)

        let list = MealItemDisplayModel(meal: makeMeal(carbs: nil), variant: .list)
        #expect(list.carbsLabel == nil)
    }

    @Test("list variant renders timestamp and macro labels, omitting nils")
    func listVariant() {
        let model = MealItemDisplayModel(
            meal: makeMeal(protein: 12, fat: nil, calories: 320),
            variant: .list
        )
        #expect(model.timestampLabel != nil)
        #expect(model.macroLabels == ["12g P", "320 kcal"])
    }

    @Test("list variant with no macros renders an empty macro row")
    func listVariantNoMacros() {
        let model = MealItemDisplayModel(meal: makeMeal(), variant: .list)
        #expect(model.macroLabels.isEmpty)
    }

    @Test("long names are never clipped in the model — truncation is rendering-only")
    func longNameUnclipped() {
        // No trailing whitespace — MealEntry.init trims it on construction.
        let longName = String(repeating: "Very long meal name ", count: 20).trimmingCharacters(in: .whitespaces)
        let recent = MealItemDisplayModel(meal: makeMeal(description: longName), variant: .recent)
        #expect(recent.name == longName)

        let list = MealItemDisplayModel(meal: makeMeal(description: longName), variant: .list)
        #expect(list.name == longName)
    }
}
