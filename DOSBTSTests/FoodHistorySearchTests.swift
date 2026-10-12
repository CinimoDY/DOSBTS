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

    @Test("stale results are rejected — an unrelated older query cannot paint wrong rows")
    func rejectsStaleResults() {
        let recents = [meal("Bagel")]
        // The user searched "apple", cleared, and typed "bagel"; the slower
        // "apple" result lands late. Not a prefix of "bagel" -> discard entirely.
        let stale = MealHistoryResults(query: "apple", entries: [meal("Apricot jam", minutesAgo: 9000)])
        let model = FoodHistorySearchModel.make(query: "bagel", recents: recents, results: stale)

        #expect(names(model.rows) == ["Bagel"])   // no "Apricot jam"
        #expect(model.isSearching == true)        // still waiting on "bagel"
    }

    @Test("narrowing re-filters the previous result instead of collapsing the list")
    func narrowingReusesPreviousResult() {
        // "app" answered; the user typed one more character. Hits for the longer
        // needle are a subset of the shorter one's, so the old rows can be
        // re-filtered rather than dropped for the length of the debounce.
        let previous = MealHistoryResults(query: "app", entries: [
            meal("Apple crumble", minutesAgo: 5000),
            meal("Snapper fillet", minutesAgo: 6000)   // contains "app", NOT "appl"
        ])
        let model = FoodHistorySearchModel.make(query: "appl", recents: [], results: previous)

        #expect(names(model.rows) == ["Apple crumble"])  // "Snapper fillet" filtered out
        #expect(model.isSearching == true)               // old set was limit-capped
    }

    @Test("narrowing keeps recents ahead of the re-filtered DB rows")
    func narrowingStillMergesRecentsFirst() {
        let recents = [meal("Apple pie")]
        let previous = MealHistoryResults(query: "app", entries: [meal("Apple crumble", minutesAgo: 5000)])
        let model = FoodHistorySearchModel.make(query: "appl", recents: recents, results: previous)
        #expect(names(model.rows) == ["Apple pie", "Apple crumble"])
        #expect(model.isSearching == true)
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
        #expect(FoodHistorySearchModel.normalizedQuery(long).count == FoodHistorySearchModel.maxQueryLength)
    }

    /// 500th character lands inside a whitespace run, so the clamp leaves a
    /// trailing space that a second trim would eat.
    private static let boundaryWhitespaceQuery =
        String(repeating: "a", count: 495) + "     " + String(repeating: "b", count: 100)

    @Test("normalizedQuery is NOT idempotent — only the view may normalize")
    func normalizedQueryIsNotIdempotent() {
        let once = FoodHistorySearchModel.normalizedQuery(Self.boundaryWhitespaceQuery)
        let twice = FoodHistorySearchModel.normalizedQuery(once)

        #expect(once.count == 500)
        #expect(twice.count == 495)
        #expect(once != twice)
        // Therefore nothing downstream of the view may re-normalize: it would
        // echo `twice` while the view compares against `once`, and the sheet
        // would spin forever. The middleware echoes the query verbatim.
    }

    @Test("boundary-whitespace query resolves when the result echoes the view's key verbatim")
    func boundaryWhitespaceQueryResolves() {
        let raw = Self.boundaryWhitespaceQuery
        let dispatched = FoodHistorySearchModel.normalizedQuery(raw)   // what the view sends
        let model = FoodHistorySearchModel.make(
            query: raw,
            recents: [],
            results: MealHistoryResults(query: dispatched, entries: [meal("Anything")])
        )
        #expect(model.isSearching == false)
        #expect(names(model.rows) == ["Anything"])
    }

    @Test("re-normalizing downstream would strand the spinner (regression guard)")
    func reNormalizedEchoWouldStrand() {
        let raw = Self.boundaryWhitespaceQuery
        let reNormalized = FoodHistorySearchModel.normalizedQuery(
            FoodHistorySearchModel.normalizedQuery(raw)
        )
        let model = FoodHistorySearchModel.make(
            query: raw,
            recents: [],
            results: MealHistoryResults(query: reNormalized, entries: [meal("Anything")])
        )
        // The re-normalized key is a strict PREFIX of what the view is waiting
        // for, so this lands on the narrowing path rather than the stale path —
        // but either way `isSearching` never goes false and no fresh dispatch is
        // pending, so the spinner is stuck permanently. This is the shape the
        // middleware must never produce.
        #expect(model.isSearching == true)
        #expect(model.rows.isEmpty)
    }

    @Test("dedupe folds non-ASCII case too, unlike SQL COLLATE NOCASE")
    func dedupeFoldsUmlauts() {
        let recents = [meal("Müsli")]
        let results = MealHistoryResults(query: "müsli", entries: [
            meal("MÜSLI", minutesAgo: 5000),
            meal("Müsli mit Äpfeln", minutesAgo: 6000)
        ])
        let model = FoodHistorySearchModel.make(query: "müsli", recents: recents, results: results)
        // "MÜSLI" collapses into the recent "Müsli"; the distinct food survives.
        #expect(names(model.rows) == ["Müsli", "Müsli mit Äpfeln"])
    }

    @Test("in-memory filter matches umlauts case-insensitively")
    func localFilterFoldsUmlauts() {
        let recents = [meal("Äpfel mit Zimt"), meal("Bagel", minutesAgo: 10)]
        let model = FoodHistorySearchModel.make(query: "äpfel", recents: recents, results: nil)
        #expect(names(model.rows) == ["Äpfel mit Zimt"])
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

// MARK: - Staging plate item candidates (DMNC-1561)

private func favorite(_ name: String, carbs: Double? = 10) -> FavoriteFood {
    FavoriteFood(mealDescription: name, carbsGrams: carbs)
}

private func personal(_ name: String, carbs: Double = 10) -> PersonalFood {
    PersonalFood(name: name, carbsG: carbs)
}

@Suite("Food Item Candidate Ranker")
struct FoodItemCandidateRankerTests {

    @Test("prefix matches rank before substring matches")
    func prefixBeforeContains() {
        let result = FoodItemCandidateRanker.rank(
            query: "pop",
            favorites: [favorite("Lollipop")],
            recents: [meal("Popsicle")],
            personalFoods: [personal("Popcorn", carbs: 20)]
        )
        #expect(result.map(\.name) == ["Popcorn", "Popsicle", "Lollipop"])
        #expect(result.first?.carbsG == 20)
        #expect(result.first?.source == .personal)
    }

    @Test("within a tier: favourites, then PersonalFood, then recents")
    func sourceOrder() {
        let result = FoodItemCandidateRanker.rank(
            query: "pop",
            favorites: [favorite("Popsicle")],
            recents: [meal("Pop tart")],
            personalFoods: [personal("Popcorn")]
        )
        #expect(result.map(\.source) == [.favorite, .personal, .meal])
    }

    @Test("dedupes case-insensitively; the earlier source wins")
    func dedupe() {
        let result = FoodItemCandidateRanker.rank(
            query: "popcorn",
            favorites: [favorite("Popcorn", carbs: 30)],
            recents: [meal("POPCORN")],
            personalFoods: [personal("popcorn", carbs: 20)]
        )
        #expect(result.count == 1)
        #expect(result.first?.source == .favorite)
        #expect(result.first?.carbsG == 30)
    }

    @Test("non-ASCII case folding matches and dedupes (äpfel / Äpfel)")
    func nonASCII() {
        let result = FoodItemCandidateRanker.rank(
            query: "äpfel",
            favorites: [],
            recents: [meal("Äpfel")],
            personalFoods: [personal("Bratäpfel"), personal("ÄPFEL")]
        )
        #expect(result.map(\.name) == ["ÄPFEL", "Bratäpfel"])
    }

    @Test("caps at the limit (default 20)")
    func cap() {
        let many = (0..<30).map { personal("Popcorn \($0)") }
        #expect(FoodItemCandidateRanker.rank(query: "pop", favorites: [], recents: [], personalFoods: many).count == 20)
        #expect(FoodItemCandidateRanker.rank(query: "pop", favorites: [], recents: [], personalFoods: many, limit: 5).count == 5)
    }

    @Test("blank query returns nothing; missing favourite carbs read as 0")
    func edges() {
        #expect(FoodItemCandidateRanker.rank(query: "  ", favorites: [favorite("Popcorn")], recents: [], personalFoods: []).isEmpty)
        let result = FoodItemCandidateRanker.rank(query: "tea", favorites: [favorite("Tea", carbs: nil)], recents: [], personalFoods: [])
        #expect(result.first?.carbsG == 0)
    }
}

@Suite("Staging Plate Item Search State")
struct PlateItemSearchStateTests {

    @Test("setPlateItemSearchResults stores, nil clears, and it is transient")
    func storesAndClears() {
        var state: DirectState = AppState(defaults: makeTestDefaults())
        let results = PlateItemSearchResults(query: "pop", personalFoods: [personal("Popcorn")], mealEntries: [])
        reduce(&state, .setPlateItemSearchResults(results: results))
        #expect(state.plateItemSearchResults?.query == "pop")
        reduce(&state, .searchPlateItems(query: "popc"))
        #expect(state.plateItemSearchResults?.query == "pop")
        reduce(&state, .setPlateItemSearchResults(results: nil))
        #expect(state.plateItemSearchResults == nil)
    }

    @Test("item-scoped analysis: loading, result and error are per row and never touch foodAnalysisResult")
    func itemAnalysis() {
        var state: DirectState = AppState(defaults: makeTestDefaults())
        let rowA = UUID()
        let rowB = UUID()
        let estimate = NutritionEstimate(
            description: "Popcorn",
            items: [NutritionItem(name: "Popcorn", carbsG: 20)],
            totalCarbsG: 20,
            confidence: .medium
        )

        reduce(&state, .analyzeFoodItem(itemID: rowA, query: "popcorn"))
        #expect(state.foodItemAnalysisLoadingItemID == rowA)

        reduce(&state, .setFoodItemAnalysisResult(itemID: rowA, estimate: estimate))
        #expect(state.foodItemAnalysisLoadingItemID == nil)
        #expect(state.foodItemAnalysisResult?.itemID == rowA)
        #expect(state.foodAnalysisResult == nil)

        reduce(&state, .analyzeFoodItem(itemID: rowB, query: "crisps"))
        #expect(state.foodItemAnalysisResult == nil)
        reduce(&state, .setFoodItemAnalysisError(itemID: rowB, error: "nope"))
        #expect(state.foodItemAnalysisError == FoodItemAnalysisError(itemID: rowB, message: "nope"))
        #expect(state.foodItemAnalysisLoadingItemID == nil)

        reduce(&state, .resetFoodItemAnalysis)
        #expect(state.foodItemAnalysisError == nil)
        #expect(state.foodItemAnalysisResult == nil)
    }
}


@Suite("Staging Plate Item Analysis — stale answers")
struct PlateItemAnalysisStaleTests {
    private let estimate = NutritionEstimate(
        description: "Popcorn",
        items: [NutritionItem(name: "Popcorn", carbsG: 20)],
        totalCarbsG: 20,
        confidence: .medium
    )

    @Test("an answer for a row that is not waiting is dropped")
    func dropsStaleAnswers() {
        var state: DirectState = AppState(defaults: makeTestDefaults())
        let rowA = UUID()
        let rowB = UUID()

        // Nothing waiting at all (e.g. the panel was closed → reset).
        reduce(&state, .setFoodItemAnalysisResult(itemID: rowA, estimate: estimate))
        #expect(state.foodItemAnalysisResult == nil)

        // Row B is waiting; a late answer for row A must not land.
        reduce(&state, .analyzeFoodItem(itemID: rowB, query: "crisps"))
        reduce(&state, .setFoodItemAnalysisResult(itemID: rowA, estimate: estimate))
        reduce(&state, .setFoodItemAnalysisError(itemID: rowA, error: "late"))
        #expect(state.foodItemAnalysisResult == nil)
        #expect(state.foodItemAnalysisError == nil)
        #expect(state.foodItemAnalysisLoadingItemID == rowB)

        // After a reset, B's own answer is stale too.
        reduce(&state, .resetFoodItemAnalysis)
        reduce(&state, .setFoodItemAnalysisResult(itemID: rowB, estimate: estimate))
        #expect(state.foodItemAnalysisResult == nil)
    }
}

@Suite("Shared food-name helpers")
struct FoodNameHelperTests {

    @Test("distinctNameMatches: contains, non-ASCII folding, first wins, limit after filter")
    func distinctNameMatches() {
        let names = ["Bratäpfel", "Banana", "ÄPFEL", "Äpfel", "äpfel pie", "Apfelmus"]
        let result = FoodNameSearch.distinctNameMatches(names, needle: "äpfel", limit: 10) { $0 }
        #expect(result == ["Bratäpfel", "ÄPFEL", "äpfel pie"])
        #expect(FoodNameSearch.distinctNameMatches(names, needle: "äpfel", limit: 2) { $0 } == ["Bratäpfel", "ÄPFEL"])
        #expect(FoodNameSearch.distinctNameMatches(names, needle: "", limit: 10) { $0 }.isEmpty)
    }

    @Test("SpeechContextPhrases: trims, drops blanks, dedupes folded, keeps order, caps")
    func speechContextPhrases() {
        let phrases = SpeechContextPhrases.make(["  Müsli ", "", "MÜSLI", "Oat milk", "   "])
        #expect(phrases == ["Müsli", "Oat milk"])
        let many = (0..<150).map { "Food \($0)" }
        #expect(SpeechContextPhrases.make(many).count == 100)
        #expect(SpeechContextPhrases.make(many, cap: 3) == ["Food 0", "Food 1", "Food 2"])
    }
}
