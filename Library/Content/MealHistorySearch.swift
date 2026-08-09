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
    /// The normalized (trimmed + clamped) query these entries answer.
    /// Produced by `FoodHistorySearchModel.normalizedQuery(_:)` — the dispatch
    /// site and the staleness check must both go through it or a query can
    /// never match its own result.
    let query: String

    /// Distinct meals matching `query`, newest first.
    let entries: [MealEntry]

    init(query: String, entries: [MealEntry]) {
        self.query = query
        self.entries = entries
    }
}
