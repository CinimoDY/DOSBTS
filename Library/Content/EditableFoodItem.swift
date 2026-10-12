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

// MARK: - Factories

extension EditableFoodItem {
    /// The one way a sourced row is built (DMNC-1561): a known serving sets the
    /// amount field and the carbs-per-gram link; no serving leaves both off.
    static func make(name: String, carbsG: Double, servingG: Double?, originalIndex: Int?, source: ItemSource) -> EditableFoodItem {
        let serving = servingG.flatMap { $0 > 0 ? $0 : nil }
        return EditableFoodItem(
            name: name,
            carbsG: carbsG,
            baseServingG: serving,
            currentAmountG: serving,
            carbsPerG: serving.map { carbsG / $0 },
            originalIndex: originalIndex,
            source: source
        )
    }

    /// Numeric grams/ml from a serving string like "per 100g", "1 serving (30g)", "15 g".
    static func servingGrams(from servingSize: String?) -> Double? {
        guard let s = servingSize else { return nil }
        let pattern = #"(\d+(?:\.\d+)?)\s*(?:g|ml|gram)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let range = Range(match.range(at: 1), in: s),
              let value = Double(s[range]),
              value > 0, value <= 2000 else { return nil }
        return value
    }
}

// MARK: - Item-scoped AI answer → one row

extension NutritionEstimate {
    /// What an item-scoped ASK AI answer writes into its row (DMNC-1561). One
    /// item: that item, with its serving. Several ("popcorn with butter" →
    /// popcorn + butter): the summed carbs under the estimate's description,
    /// with no serving — a per-gram link across mixed items would be fiction.
    /// nil when the AI identified nothing.
    var singleRowReplacement: (name: String, carbsG: Double, servingG: Double?)? {
        switch items.count {
        case 0:
            return nil
        case 1:
            let item = items[0]
            return (item.name, item.carbsG, EditableFoodItem.servingGrams(from: item.servingSize))
        default:
            let name = description.trimmingCharacters(in: .whitespacesAndNewlines)
            return (name.isEmpty ? items.map(\.name).joined(separator: ", ") : name,
                    items.reduce(0) { $0 + $1.carbsG },
                    nil)
        }
    }
}
