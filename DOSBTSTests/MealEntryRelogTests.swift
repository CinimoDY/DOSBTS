//
//  MealEntryRelogTests.swift
//  DOSBTSTests
//

import Foundation
import Testing
@testable import DOSBTSApp

@Suite("MealEntry.toNutritionEstimate")
struct MealEntryRelogTests {

    // MARK: - Fallback path (no analysisSessionId)

    @Test("no analysisSessionId produces single aggregate item")
    func aggregateFallback_noSessionId() {
        let meal = MealEntry(
            timestamp: Date(),
            mealDescription: "Pasta",
            carbsGrams: 60,
            proteinGrams: 12,
            fatGrams: 8,
            calories: 360,
            fiberGrams: 3
        )
        let estimate = meal.toNutritionEstimate(personalFoods: [])
        #expect(estimate.items.count == 1)
        #expect(estimate.items[0].name == "Pasta")
        #expect(estimate.items[0].carbsG == 60)
        #expect(estimate.items[0].proteinG == 12)
        #expect(estimate.items[0].fatG == 8)
        #expect(estimate.items[0].calories == 360)
        #expect(estimate.items[0].fiberG == 3)
        #expect(estimate.totalCarbsG == 60)
        #expect(estimate.confidence == .high)
    }

    @Test("empty mealDescription falls back to 'Meal' label")
    func aggregateFallback_emptyDescription() {
        let meal = MealEntry(
            timestamp: Date(),
            mealDescription: "",
            carbsGrams: 30
        )
        let estimate = meal.toNutritionEstimate(personalFoods: [])
        #expect(estimate.items[0].name == "Meal")
    }

    @Test("nil carbsGrams maps to 0 in aggregate fallback")
    func aggregateFallback_nilCarbs() {
        let meal = MealEntry(
            timestamp: Date(),
            mealDescription: "Unknown",
            carbsGrams: nil
        )
        let estimate = meal.toNutritionEstimate(personalFoods: [])
        #expect(estimate.items[0].carbsG == 0)
        #expect(estimate.totalCarbsG == 0)
    }

    // MARK: - Linked PersonalFood path

    @Test("analysisSessionId with matching PersonalFood items restores per-item breakdown")
    func linkedPath_matchingPersonalFoods() {
        let sessionId = UUID()
        let meal = MealEntry(
            timestamp: Date(),
            mealDescription: "Rice and beans",
            carbsGrams: 55,
            analysisSessionId: sessionId
        )
        let foods = [
            PersonalFood(name: "Rice", carbsG: 40, analysisSessionId: sessionId),
            PersonalFood(name: "Beans", carbsG: 15, analysisSessionId: sessionId),
        ]
        let estimate = meal.toNutritionEstimate(personalFoods: foods)
        #expect(estimate.items.count == 2)
        let names = estimate.items.map(\.name)
        #expect(names.contains("Rice"))
        #expect(names.contains("Beans"))
        let riceItem = estimate.items.first(where: { $0.name == "Rice" })
        #expect(riceItem?.carbsG == 40)
        let beansItem = estimate.items.first(where: { $0.name == "Beans" })
        #expect(beansItem?.carbsG == 15)
    }

    @Test("analysisSessionId with no matching PersonalFood falls back to aggregate")
    func linkedPath_noMatchingPersonalFoods() {
        let sessionId = UUID()
        let otherSessionId = UUID()
        let meal = MealEntry(
            timestamp: Date(),
            mealDescription: "Pizza",
            carbsGrams: 70,
            analysisSessionId: sessionId
        )
        let unrelatedFood = PersonalFood(name: "Rice", carbsG: 40, analysisSessionId: otherSessionId)
        let estimate = meal.toNutritionEstimate(personalFoods: [unrelatedFood])
        #expect(estimate.items.count == 1)
        #expect(estimate.items[0].name == "Pizza")
        #expect(estimate.items[0].carbsG == 70)
    }

    @Test("analysisSessionId with empty personalFoods array falls back to aggregate")
    func linkedPath_emptyPersonalFoods() {
        let sessionId = UUID()
        let meal = MealEntry(
            timestamp: Date(),
            mealDescription: "Sandwich",
            carbsGrams: 45,
            analysisSessionId: sessionId
        )
        let estimate = meal.toNutritionEstimate(personalFoods: [])
        #expect(estimate.items.count == 1)
        #expect(estimate.items[0].name == "Sandwich")
    }

    @Test("PersonalFood items from a different session are not included")
    func linkedPath_filtersToCorrectSession() {
        let sessionId = UUID()
        let otherSessionId = UUID()
        let meal = MealEntry(
            timestamp: Date(),
            mealDescription: "Oats",
            carbsGrams: 30,
            analysisSessionId: sessionId
        )
        let foods = [
            PersonalFood(name: "Oats", carbsG: 30, analysisSessionId: sessionId),
            PersonalFood(name: "Banana", carbsG: 25, analysisSessionId: otherSessionId),
        ]
        let estimate = meal.toNutritionEstimate(personalFoods: foods)
        #expect(estimate.items.count == 1)
        #expect(estimate.items[0].name == "Oats")
    }

    // MARK: - Favourite staging path (DMNC-796 U3)

    @Test("favourite toMealEntry hydrates as single aggregate item carrying name and carbs")
    func favouriteStagingHydration() {
        // Covers F1: favourites never carry analysisSessionId, so staging
        // always takes the aggregate fallback with the favourite's values.
        let favorite = FavoriteFood(
            mealDescription: "Oat milk latte",
            carbsGrams: 14,
            sortOrder: 0
        )
        let meal = favorite.toMealEntry()
        #expect(meal.analysisSessionId == nil)

        let estimate = meal.toNutritionEstimate(personalFoods: [])
        #expect(estimate.items.count == 1)
        #expect(estimate.items[0].name == "Oat milk latte")
        #expect(estimate.items[0].carbsG == 14)
    }

    // MARK: - Hashable

    @Test("MealEntry hashes by id")
    func hashableById() {
        let meal = MealEntry(timestamp: Date(), mealDescription: "Test", carbsGrams: 10)
        var set = Set<MealEntry>()
        set.insert(meal)
        set.insert(meal)
        #expect(set.count == 1)
    }
}
