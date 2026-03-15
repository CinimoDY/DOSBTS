//
//  FavoriteFood.swift
//  DOSBTS
//

import Foundation

// MARK: - FavoriteFood

struct FavoriteFood: CustomStringConvertible, Codable, Identifiable {
    // MARK: Lifecycle

    init(mealDescription: String, carbsGrams: Double?, proteinGrams: Double? = nil, fatGrams: Double? = nil, calories: Double? = nil, fiberGrams: Double? = nil, sortOrder: Int = 0, isHypoTreatment: Bool = false) {
        self.id = UUID()
        self.mealDescription = mealDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        self.carbsGrams = carbsGrams
        self.proteinGrams = proteinGrams
        self.fatGrams = fatGrams
        self.calories = calories
        self.fiberGrams = fiberGrams
        self.sortOrder = sortOrder
        self.isHypoTreatment = isHypoTreatment
        self.lastUsed = nil
    }

    init(id: UUID, mealDescription: String, carbsGrams: Double?, proteinGrams: Double? = nil, fatGrams: Double? = nil, calories: Double? = nil, fiberGrams: Double? = nil, sortOrder: Int = 0, isHypoTreatment: Bool = false, lastUsed: Date? = nil) {
        self.id = id
        self.mealDescription = mealDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        self.carbsGrams = carbsGrams
        self.proteinGrams = proteinGrams
        self.fatGrams = fatGrams
        self.calories = calories
        self.fiberGrams = fiberGrams
        self.sortOrder = sortOrder
        self.isHypoTreatment = isHypoTreatment
        self.lastUsed = lastUsed
    }

    // MARK: Internal

    let id: UUID
    let mealDescription: String
    let carbsGrams: Double?
    let proteinGrams: Double?
    let fatGrams: Double?
    let calories: Double?
    let fiberGrams: Double?
    let sortOrder: Int
    let isHypoTreatment: Bool
    let lastUsed: Date?

    var description: String {
        "{ id: \(id), mealDescription: \(mealDescription), carbsGrams: \(carbsGrams ?? 0) }"
    }
}

// MARK: Equatable

extension FavoriteFood: Equatable {
    static func == (lhs: FavoriteFood, rhs: FavoriteFood) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Factory Methods

extension FavoriteFood {
    static func from(mealEntry: MealEntry) -> FavoriteFood {
        FavoriteFood(
            mealDescription: mealEntry.mealDescription,
            carbsGrams: mealEntry.carbsGrams,
            proteinGrams: mealEntry.proteinGrams,
            fatGrams: mealEntry.fatGrams,
            calories: mealEntry.calories,
            fiberGrams: mealEntry.fiberGrams
        )
    }

    func toMealEntry() -> MealEntry {
        MealEntry(
            timestamp: Date(),
            mealDescription: mealDescription,
            carbsGrams: carbsGrams,
            proteinGrams: proteinGrams,
            fatGrams: fatGrams,
            calories: calories,
            fiberGrams: fiberGrams
        )
    }
}
