//
//  FoodItemCandidate.swift
//  DOSBTS
//
//  Item-level replacement candidates for the staging plate's REPLACE panel
//  (DMNC-1561). Pure and in-memory: the view feeds it the loaded favourites,
//  recents and PersonalFood rows merged with the DB hits from
//  `.searchPlateItems`, and renders whatever comes back.
//
//  Matching is `localizedCaseInsensitiveContains` and dedupe is `lowercased()` —
//  NEVER SQL `LIKE`/`NOCASE`, which fold ASCII only and silently miss
//  `äpfel`/`Äpfel` (docs/solutions/logic-errors/sqlite-like-folds-ascii-only-non-ascii-search-misses-20260809.md).
//

import Foundation

// MARK: - FoodItemCandidate

struct FoodItemCandidate: Equatable, Identifiable {
    enum Source: String, Equatable {
        case favorite
        case personal
        /// A past MealEntry — a WHOLE meal, so its carbs are the meal's, not
        /// a per-item figure. Labelled MEAL so the row says so.
        case meal

        /// Tag shown at the end of the candidate row.
        var label: String {
            switch self {
            case .favorite: return "FAV"
            case .personal: return "PERSONAL"
            case .meal: return "MEAL"
            }
        }
    }

    let name: String
    let carbsG: Double
    let source: Source
    /// Portion in g/ml when the source knows one; nil otherwise (none of the
    /// current sources store a serving, so this is reserved for catalog work).
    var servingG: Double? = nil

    /// Names are deduped case-insensitively, so the folded name is unique.
    var id: String { name.lowercased() }
}

// MARK: - FoodItemCandidateRanker

enum FoodItemCandidateRanker {
    static let defaultLimit = 20

    /// Candidates whose name contains `query`, deduped by lowercased name.
    ///
    /// Order: names that START with the query before names that merely contain
    /// it; within each tier favourites → PersonalFood → recents, each source in
    /// the order given. The first occurrence of a name wins, so a favourite
    /// shadows the same food in PersonalFood and recents.
    static func rank(
        query: String,
        favorites: [FavoriteFood],
        recents: [MealEntry],
        personalFoods: [PersonalFood],
        limit: Int = defaultLimit
    ) -> [FoodItemCandidate] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, limit > 0 else { return [] }

        let all: [FoodItemCandidate] =
            favorites.map { FoodItemCandidate(name: $0.mealDescription, carbsG: $0.carbsGrams ?? 0, source: .favorite) }
            + personalFoods.map { FoodItemCandidate(name: $0.name, carbsG: $0.carbsG, source: .personal) }
            + recents.map { FoodItemCandidate(name: $0.mealDescription, carbsG: $0.carbsGrams ?? 0, source: .meal) }

        let matches = FoodNameSearch.distinctNameMatches(
            all.map { FoodItemCandidate(name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines), carbsG: $0.carbsG, source: $0.source) },
            needle: needle,
            limit: .max,
            name: \.name
        )

        var prefixTier: [FoodItemCandidate] = []
        var containsTier: [FoodItemCandidate] = []
        for candidate in matches {
            if isPrefixMatch(candidate.name, needle) {
                prefixTier.append(candidate)
            } else {
                containsTier.append(candidate)
            }
        }

        return Array((prefixTier + containsTier).prefix(limit))
    }

    /// Case- and width-insensitive anchored match, locale-aware like the
    /// contains filter (so `Äpfel` starts with `äp`).
    private static func isPrefixMatch(_ name: String, _ needle: String) -> Bool {
        name.range(of: needle, options: [.caseInsensitive, .anchored], locale: .current) != nil
    }
}

// MARK: - PlateItemSearchResults

/// One answered `.searchPlateItems` query: DB-backed PersonalFood and
/// single-name meal hits beyond what the loaded state holds (PersonalFood is
/// capped at 12 in memory, recents at 50).
///
/// Carries the query it answered for the same reason `MealHistoryResults` does:
/// `Store.dispatch` never cancels in-flight publishers, so an older, slower
/// search can land last. The panel drops results whose `query` is not the one
/// it is currently showing.
struct PlateItemSearchResults: Equatable {
    /// Echoed byte-for-byte as dispatched — never re-normalized downstream.
    let query: String
    let personalFoods: [PersonalFood]
    let mealEntries: [MealEntry]
}

// MARK: - Item-scoped AI analysis (ASK AI on one plate row)

/// The answer to `.analyzeFoodItem(itemID:query:)`. Lives apart from
/// `foodAnalysisResult` on purpose: writing that would replace the whole plate.
struct FoodItemAnalysisResult {
    /// Fresh per landing, so the plate can observe a second answer for the
    /// same row.
    let id = UUID()
    let itemID: UUID
    let estimate: NutritionEstimate
}

struct FoodItemAnalysisError: Equatable {
    let itemID: UUID
    let message: String
}
