//
//  FoodHistorySearchTests.swift
//  DOSBTSTests
//
//  Pins DB-backed food history search (DMNC-1484, lane A1):
//    - the reducer stores/clears `mealHistoryResults` and never persists it;
//    - `FoodHistorySearchModel` merges recents with DB hits, dedupes by name,
//      and — the hazard this feature actually has — REJECTS results answering a
//      stale query, because `Store.dispatch` never cancels in-flight publishers.
//

import Foundation
import Testing
@testable import DOSBTSApp

// MARK: - Helpers

private func reduce(_ state: inout DirectState, _ action: DirectAction) {
    directReducer(state: &state, action: action)
}

/// Distinct timestamps so ordering assertions are unambiguous.
private func meal(_ description: String, minutesAgo: Int = 0) -> MealEntry {
    MealEntry(
        timestamp: Date(timeIntervalSince1970: 1_700_000_000 - Double(minutesAgo) * 60),
        mealDescription: description,
        carbsGrams: 30
    )
}

private func names(_ entries: [MealEntry]) -> [String] {
    entries.map(\.mealDescription)
}

// MARK: - Reducer

@Suite("Food History Search State")
struct FoodHistorySearchStateTests {

    @Test("setMealHistoryResults stores results and nil clears them")
    func setMealHistoryResults() {
        var state: DirectState = AppState(defaults: makeTestDefaults())
        #expect(state.mealHistoryResults == nil)

        let results = MealHistoryResults(query: "app", entries: [meal("Apple pie")])
        reduce(&state, .setMealHistoryResults(results: results))
        #expect(state.mealHistoryResults?.query == "app")
        #expect(state.mealHistoryResults?.entries.count == 1)

        reduce(&state, .setMealHistoryResults(results: nil))
        #expect(state.mealHistoryResults == nil)
    }

    @Test("mealHistoryResults is transient — not persisted to UserDefaults")
    func mealHistoryResultsIsTransient() {
        let defaults = makeTestDefaults()
        var state: DirectState = AppState(defaults: defaults)
        reduce(&state, .setMealHistoryResults(
            results: MealHistoryResults(query: "app", entries: [meal("Apple pie")])
        ))
        #expect(state.mealHistoryResults != nil)

        // A fresh AppState over the same defaults must not see the results.
        let fresh: DirectState = AppState(defaults: defaults)
        #expect(fresh.mealHistoryResults == nil)
    }

    @Test("searchMealHistory has no reducer case — it must not mutate state")
    func searchMealHistoryDoesNotMutate() {
        var state: DirectState = AppState(defaults: makeTestDefaults())
        let results = MealHistoryResults(query: "app", entries: [meal("Apple pie")])
        reduce(&state, .setMealHistoryResults(results: results))

        // Falling through `default:` is what lets the view treat "no result for
        // my query" as the loading state; a reducer case would break that.
        reduce(&state, .searchMealHistory(query: "apple"))
        #expect(state.mealHistoryResults?.query == "app")
    }
}

// MARK: - Pure merge model

@Suite("FoodHistorySearchModel")
struct FoodHistorySearchModelTests {

    @Test("empty query shows all recents untouched, not searching")
    func emptyQuery() {
        let recents = [meal("Apple pie"), meal("Bagel", minutesAgo: 10)]
        let model = FoodHistorySearchModel.make(query: "   ", recents: recents, results: nil)
        #expect(names(model.rows) == ["Apple pie", "Bagel"])
        #expect(model.isSearching == false)
    }

    @Test("below the 3-char threshold: in-memory filter only, never searching")
    func belowThreshold() {
        let recents = [meal("Apple pie"), meal("Bagel", minutesAgo: 10)]
        let model = FoodHistorySearchModel.make(query: "ap", recents: recents, results: nil)
        #expect(names(model.rows) == ["Apple pie"])
        #expect(model.isSearching == false)
    }

    @Test("threshold is 3 and matches the ASK AI gate")
    func thresholdValue() {
        #expect(FoodHistorySearchModel.minQueryLength == 3)
    }

    @Test("at the threshold with no result yet: local rows plus searching")
    func awaitingResults() {
        let recents = [meal("Apple pie"), meal("Bagel", minutesAgo: 10)]
        let model = FoodHistorySearchModel.make(query: "app", recents: recents, results: nil)
        #expect(names(model.rows) == ["Apple pie"])
        #expect(model.isSearching == true)
    }

    @Test("DB hits append below recents; recents win over duplicates")
    func mergeAppendsDBHits() {
        let recents = [meal("Apple pie"), meal("Bagel", minutesAgo: 10)]
        let results = MealHistoryResults(query: "app", entries: [
            meal("Apple pie", minutesAgo: 5000),      // duplicate of a recent
            meal("Apple crumble", minutesAgo: 6000)   // only reachable via the DB
        ])
        let model = FoodHistorySearchModel.make(query: "app", recents: recents, results: results)
        #expect(names(model.rows) == ["Apple pie", "Apple crumble"])
        #expect(model.isSearching == false)
    }

    @Test("dedupe is case-insensitive")
    func dedupeIsCaseInsensitive() {
        let recents = [meal("Apple Pie")]
        let results = MealHistoryResults(query: "app", entries: [
            meal("APPLE PIE", minutesAgo: 5000),
            meal("apple pie", minutesAgo: 6000)
        ])
        let model = FoodHistorySearchModel.make(query: "app", recents: recents, results: results)
        #expect(names(model.rows) == ["Apple Pie"])
    }

    @Test("DB hits are deduped against each other, first (newest) wins")
    func dedupeWithinDBHits() {
        let results = MealHistoryResults(query: "app", entries: [
            meal("Apple crumble", minutesAgo: 5000),
            meal("apple CRUMBLE", minutesAgo: 9000)
        ])
        let model = FoodHistorySearchModel.make(query: "app", recents: [], results: results)
        #expect(model.rows.count == 1)
        #expect(model.rows.first?.timestamp == results.entries.first?.timestamp)
    }

    @Test("stale results are rejected — a slow older query cannot paint wrong rows")
    func rejectsStaleResults() {
        let recents = [meal("Apple pie")]
        // The user has typed "appl"; the in-flight "app" result lands late.
        let stale = MealHistoryResults(query: "app", entries: [meal("Apricot jam", minutesAgo: 9000)])
        let model = FoodHistorySearchModel.make(query: "appl", recents: recents, results: stale)

        #expect(names(model.rows) == ["Apple pie"])   // no "Apricot jam"
        #expect(model.isSearching == true)            // still waiting on "appl"
    }

    @Test("results whose query only differs by whitespace still match (normalization)")
    func normalizationMatchesResults() {
        let results = MealHistoryResults(query: "app", entries: [meal("Apple crumble", minutesAgo: 9000)])
        let model = FoodHistorySearchModel.make(query: "  app  ", recents: [], results: results)
        #expect(names(model.rows) == ["Apple crumble"])
        #expect(model.isSearching == false)
    }

    @Test("normalizedQuery trims and clamps to the ASK AI limit")
    func normalizedQueryClamps() {
        #expect(FoodHistorySearchModel.normalizedQuery("  chicken \n") == "chicken")

        let long = String(repeating: "a", count: 900)
        let normalized = FoodHistorySearchModel.normalizedQuery(long)
        #expect(normalized.count == FoodHistorySearchModel.maxQueryLength)
        // Normalization must be idempotent, or a clamped query could never
        // match the result the middleware echoes back.
        #expect(FoodHistorySearchModel.normalizedQuery(normalized) == normalized)
    }

    @Test("empty result set for the current query yields the honest empty state")
    func emptyResultsAreNotLoading() {
        let model = FoodHistorySearchModel.make(
            query: "zzz",
            recents: [meal("Apple pie")],
            results: MealHistoryResults(query: "zzz", entries: [])
        )
        #expect(model.rows.isEmpty)
        #expect(model.isSearching == false)   // "No matches", not a spinner
    }
}
