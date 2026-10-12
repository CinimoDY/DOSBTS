//
//  EditableFoodItem.swift
//  DOSBTS
//

import Foundation

// MARK: - ItemSource

/// Where a staged plate item's current name/carbs came from. Provenance only —
/// it never changes the carb math. DMNC-1561.
enum ItemSource: String, Equatable {
    case ai
    case barcode
    case history
    case manual
}

// MARK: - EditableFoodItem

/// Staging plate item — editable copy of a NutritionItem
struct EditableFoodItem: Identifiable {
    var id = UUID()
    var name: String
    var carbsG: Double
    var isExpanded: Bool = false
    var baseServingG: Double? = nil  // From OFF serving_quantity, for portion presets
    var currentAmountG: Double? = nil // User-visible portion in g/ml (nil = amount field hidden)
    var carbsPerG: Double? = nil      // Carbs-per-gram ratio (nil = user overrode carbs directly)
    /// Index of the `NutritionItem` this row was staged from in the plate's
    /// `foodAnalysisResult.items`; nil for rows the user added. Corrections are
    /// attributed through this, never through the row's current position — a
    /// mid-list delete shifts positions but not identity (DMNC-1561).
    var originalIndex: Int? = nil
    var source: ItemSource = .manual
}
