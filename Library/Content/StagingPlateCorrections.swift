//
//  StagingPlateCorrections.swift
//  DOSBTS
//
//  Pure "original estimate + edited plate → correction log" mapping (DMNC-1561).
//
//  Rows are matched to the estimate's items by `EditableFoodItem.originalIndex`,
//  NOT by their current position. The old positional match misattributed every
//  correction after a mid-list delete: deleting item 1 of [Rice, Chicken, Sauce]
//  logged "Rice → Chicken" and "Chicken → Sauce" renames plus a bogus "Sauce
//  deleted", and each of those upserts a `PersonalFood` row — poisoning the very
//  dictionary the AI prompt and the plate's item search learn from.
//

import Foundation

enum StagingPlateCorrections {
    static func compute(original: [NutritionItem], staged: [EditableFoodItem]) -> [FoodCorrection] {
        var corrections: [FoodCorrection] = []
        var matchedIndices = Set<Int>()

        for item in staged {
            let stagedName = clampName(item.name)
            let stagedCarbs = clampCarbs(item.carbsG)

            // A row only claims its original once; a (theoretical) duplicate or
            // out-of-range index is treated as a user-added row.
            guard let index = item.originalIndex,
                  original.indices.contains(index),
                  matchedIndices.insert(index).inserted
            else {
                corrections.append(FoodCorrection(
                    correctionType: .added,
                    originalName: nil,
                    correctedName: stagedName,
                    originalCarbsG: nil,
                    correctedCarbsG: stagedCarbs
                ))
                continue
            }

            let orig = original[index]
            let nameChanged = stagedName.lowercased() != orig.name.lowercased()
            let carbsChanged = abs(stagedCarbs - orig.carbsG) > 0.5

            if nameChanged {
                corrections.append(FoodCorrection(
                    correctionType: .nameChange,
                    originalName: orig.name,
                    correctedName: stagedName,
                    originalCarbsG: orig.carbsG,
                    correctedCarbsG: carbsChanged ? stagedCarbs : nil
                ))
            } else if carbsChanged {
                corrections.append(FoodCorrection(
                    correctionType: .carbChange,
                    originalName: orig.name,
                    correctedName: nil,
                    originalCarbsG: orig.carbsG,
                    correctedCarbsG: stagedCarbs
                ))
            }
        }

        // Every original item no row claims was deleted.
        for (index, orig) in original.enumerated() where !matchedIndices.contains(index) {
            corrections.append(FoodCorrection(
                correctionType: .deleted,
                originalName: orig.name,
                correctedName: nil,
                originalCarbsG: orig.carbsG,
                correctedCarbsG: nil
            ))
        }

        return corrections
    }

    private static func clampName(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
    }

    private static func clampCarbs(_ value: Double) -> Double {
        max(0, min(value, 10000))
    }
}
