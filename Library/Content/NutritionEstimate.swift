//
//  NutritionEstimate.swift
//  DOSBTS
//

import Foundation

// MARK: - NutritionEstimate

struct NutritionEstimate: Codable {
    var description: String
    var items: [NutritionItem]
    var totalCarbsG: Double
    var totalCalories: Double?
    var confidence: Confidence
    var confidenceNotes: String?

    enum Confidence: String, Codable {
        case high
        case medium
        case low
    }

    enum CodingKeys: String, CodingKey {
        case description
        case items
        case totalCarbsG = "total_carbs_g"
        case totalCalories = "total_calories"
        case confidence
        case confidenceNotes = "confidence_notes"
    }
}

// MARK: - NutritionItem

struct NutritionItem: Codable, Identifiable {
    var id: String { name }
    var name: String
    var carbsG: Double
    var proteinG: Double?
    var fatG: Double?
    var calories: Double?
    var fiberG: Double?
    var servingSize: String?

    enum CodingKeys: String, CodingKey {
        case name
        case carbsG = "carbs_g"
        case proteinG = "protein_g"
        case fatG = "fat_g"
        case calories
        case fiberG = "fiber_g"
        case servingSize = "serving_size"
    }
}

