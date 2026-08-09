//
//  MealHistorySearch.swift
//  DOSBTS
//
//  Payload for the DB-backed food history search (DMNC-1484, lane A1).
//
//  Why the query travels with its results: `Store.dispatch`
//  (Library/Extensions/State.swift) fires every middleware publisher and never
//  cancels in-flight work, so two searches can be in the air at once and the
//  slower, older one can land last. Typing `ap` then `app` would otherwise show
//  the `ap` rows underneath the `app` query. The view compares `query` against
//  the query it is currently showing and drops anything that does not match.
//

import Foundation

/// One answered food-history search: the normalized query that was asked, and
/// the distinct meals that matched it (newest first, one row per food name).
struct MealHistoryResults: Equatable {
    /// The query these entries answer, byte-for-byte as the view dispatched it.
    ///
    /// The view normalizes ONCE (`FoodHistorySearchModel.normalizedQuery(_:)`)
    /// and everything downstream echoes that string verbatim. Nothing else may
    /// re-normalize: `normalizedQuery` is trim-then-clamp and therefore NOT
    /// idempotent, so a second pass can return a shorter string that the view
    /// would never match against — a permanently stuck spinner.
    let query: String

    /// Distinct meals matching `query`, newest first.
    let entries: [MealEntry]

    init(query: String, entries: [MealEntry]) {
        self.query = query
        self.entries = entries
    }
}
