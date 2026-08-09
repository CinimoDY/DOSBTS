//
//  FavoriteStore.swift
//  DOSBTSApp
//

import Combine
import Foundation
import GRDB

func favoriteFoodStoreMiddleware() -> Middleware<DirectState, DirectAction> {
    return { state, action, _ in
        switch action {
        case .startup:
            DataStore.shared.createFavoriteFoodTable()

            return Publishers.Merge(
                Just(DirectAction.loadFavoriteFoodValues)
                    .setFailureType(to: DirectError.self),
                Just(DirectAction.loadRecentMealEntries)
                    .setFailureType(to: DirectError.self)
            ).eraseToAnyPublisher()

        case .addFavoriteFoodValues(favoriteFoodValues: let favoriteFoodValues):
            guard !favoriteFoodValues.isEmpty else {
                return Empty().eraseToAnyPublisher()
            }

            DataStore.shared.insertFavoriteFood(favoriteFoodValues)

            return Just(DirectAction.loadFavoriteFoodValues)
                .setFailureType(to: DirectError.self)
                .eraseToAnyPublisher()

        case .deleteFavoriteFood(favoriteFood: let favoriteFood):
            DataStore.shared.deleteFavoriteFood(favoriteFood)

            return Just(DirectAction.loadFavoriteFoodValues)
                .setFailureType(to: DirectError.self)
                .eraseToAnyPublisher()

        case .updateFavoriteFood(favoriteFood: let favoriteFood):
            DataStore.shared.updateFavoriteFood(favoriteFood)

            return Just(DirectAction.loadFavoriteFoodValues)
                .setFailureType(to: DirectError.self)
                .eraseToAnyPublisher()

        case .reorderFavoriteFoods(favoriteFoodValues: let favoriteFoodValues):
            DataStore.shared.reorderFavoriteFoods(favoriteFoodValues)

            return Just(DirectAction.loadFavoriteFoodValues)
                .setFailureType(to: DirectError.self)
                .eraseToAnyPublisher()

        case .loadFavoriteFoodValues:
            guard state.appState == .active else {
                return Empty().eraseToAnyPublisher()
            }

            return DataStore.shared.getFavoriteFoodValues().map { favoriteFoodValues in
                DirectAction.setFavoriteFoodValues(favoriteFoodValues: favoriteFoodValues)
            }.eraseToAnyPublisher()

        case .logFavoriteFood(favoriteFood: let favoriteFood):
            // Only updates lastUsed timestamp. The view creates the MealEntry
            // and dispatches .addMealEntry directly (same UUID for toast undo).
            DataStore.shared.updateFavoriteFoodLastUsed(favoriteFood)

            return Empty().eraseToAnyPublisher()

        // Cross-middleware listening: these actions are "owned" by mealEntryStoreMiddleware,
        // but we listen here to reload recents when meals change.
        case .addMealEntry, .deleteMealEntry:
            return Just(DirectAction.loadRecentMealEntries)
                .setFailureType(to: DirectError.self)
                .eraseToAnyPublisher()

        case .loadRecentMealEntries:
            guard state.appState == .active else {
                return Empty().eraseToAnyPublisher()
            }

            return DataStore.shared.getRecentMealEntries().map { recentMealEntries in
                DirectAction.setRecentMealEntries(recentMealEntries: recentMealEntries)
            }.eraseToAnyPublisher()

        case .searchMealHistory(query: let query):
            // Silently drops when not .active. There is deliberately no
            // .setAppState(.active) re-trigger here — the view owns re-arming,
            // because only it knows whether the sheet is still open and what the
            // field currently holds (UnifiedFoodEntryView.onChange(of: appState)).
            guard state.appState == .active else {
                break
            }

            // Echo `query` back EXACTLY as received — never a re-normalized copy.
            // The view is the sole authority on what it is waiting for, and
            // trim-then-clamp is NOT idempotent: when the 500th character lands
            // inside a whitespace run, normalizing again yields a shorter string.
            // The view would then never recognise its own result and would spin
            // forever, unrecoverable by typing (appending cannot change
            // `prefix(500)`). Pinned by `normalizedQueryIsNotIdempotent`.
            //
            // On a GRDB read error `searchMealEntries` emits `.failure`, which the
            // Store logs but never re-dispatches — so `.setMealHistoryResults`
            // would never land and the view (which treats "no result for my
            // query" as loading) would spin forever. Fall back to an empty result
            // set FOR THIS QUERY so the sheet shows its "no matches" state.
            return DataStore.shared.searchMealEntries(matching: query, limit: 50)
                .map { DirectAction.setMealHistoryResults(results: MealHistoryResults(query: query, entries: $0)) }
                .catch { error -> Just<DirectAction> in
                    DirectLog.error("Food history search failed: \(error)")
                    return Just(.setMealHistoryResults(results: MealHistoryResults(query: query, entries: [])))
                }
                .setFailureType(to: DirectError.self)
                .eraseToAnyPublisher()

        case .setAppState(appState: let appState):
            guard appState == .active else {
                return Empty().eraseToAnyPublisher()
            }

            return Publishers.Merge(
                Just(DirectAction.loadFavoriteFoodValues)
                    .setFailureType(to: DirectError.self),
                Just(DirectAction.loadRecentMealEntries)
                    .setFailureType(to: DirectError.self)
            ).eraseToAnyPublisher()

        default:
            break
        }

        return Empty().eraseToAnyPublisher()
    }
}

private extension DataStore {
    func createFavoriteFoodTable() {
        if let dbQueue = dbQueue {
            do {
                try dbQueue.write { db in
                    try db.create(table: FavoriteFood.Table, ifNotExists: true) { t in
                        t.column(FavoriteFood.Columns.id.name, .text)
                            .primaryKey()
                        t.column(FavoriteFood.Columns.mealDescription.name, .text)
                            .notNull()
                        t.column(FavoriteFood.Columns.carbsGrams.name, .double)
                        t.column(FavoriteFood.Columns.proteinGrams.name, .double)
                        t.column(FavoriteFood.Columns.fatGrams.name, .double)
                        t.column(FavoriteFood.Columns.calories.name, .double)
                        t.column(FavoriteFood.Columns.fiberGrams.name, .double)
                        t.column(FavoriteFood.Columns.sortOrder.name, .integer)
                            .notNull()
                            .defaults(to: 0)
                        t.column(FavoriteFood.Columns.isHypoTreatment.name, .boolean)
                            .notNull()
                            .defaults(to: false)
                        t.column(FavoriteFood.Columns.lastUsed.name, .date)
                    }
                }

                // Seed default hypo treatments (atomic check + insert)
                try dbQueue.write { db in
                    let count = try FavoriteFood.fetchCount(db)
                    if count == 0 {
                        try FavoriteFood(
                            mealDescription: "Dextrose tabs",
                            carbsGrams: 15,
                            proteinGrams: 0,
                            fatGrams: 0,
                            calories: 60,
                            sortOrder: 0,
                            isHypoTreatment: true
                        ).insert(db)

                        try FavoriteFood(
                            mealDescription: "Juice box",
                            carbsGrams: 25,
                            proteinGrams: 0,
                            fatGrams: 0,
                            calories: 100,
                            sortOrder: 1,
                            isHypoTreatment: true
                        ).insert(db)
                    }
                }
            } catch {
                DirectLog.error("\(error)")
            }

            // Add index on MealEntry.mealDescription for recents query
            var migrator = DatabaseMigrator()

            migrator.registerMigration("Add composite index on MealEntry for recents") { db in
                try db.execute(sql: """
                    CREATE INDEX IF NOT EXISTS MealEntry_description_timestamp
                    ON MealEntry(mealDescription COLLATE NOCASE, timestamp DESC)
                """)
            }

            migrator.registerMigration("Add FavoriteFood.shortLabel column") { db in
                if try !db.columns(in: FavoriteFood.Table).contains(where: { $0.name == FavoriteFood.Columns.shortLabel.name }) {
                    try db.alter(table: FavoriteFood.Table) { t in
                        t.add(column: FavoriteFood.Columns.shortLabel.name, .text)
                    }
                }
            }

            // Seed hypo treatment favorites for existing users who already had
            // non-hypo favorites (the initial seed above only runs when count == 0).
            migrator.registerMigration("Seed hypo treatment favorites for existing users") { db in
                let hypoCount = try FavoriteFood
                    .filter(Column(FavoriteFood.Columns.isHypoTreatment.name) == true)
                    .fetchCount(db)

                if hypoCount == 0 {
                    // Use negative sortOrder so seeded hypo items don't collide
                    // with existing user favorites that start at 0.
                    try FavoriteFood(
                        mealDescription: "Dextrose tabs",
                        carbsGrams: 15,
                        proteinGrams: 0,
                        fatGrams: 0,
                        calories: 60,
                        sortOrder: 0,
                        isHypoTreatment: true
                    ).insert(db)

                    try FavoriteFood(
                        mealDescription: "Juice box",
                        carbsGrams: 25,
                        proteinGrams: 0,
                        fatGrams: 0,
                        calories: 100,
                        sortOrder: 1,
                        isHypoTreatment: true
                    ).insert(db)
                }
            }

            do {
                try migrator.migrate(dbQueue)
            } catch {
                DirectLog.error("\(error)")
            }
        }
    }

    func insertFavoriteFood(_ values: [FavoriteFood]) {
        if let dbQueue = dbQueue {
            do {
                try dbQueue.write { db in
                    values.forEach { value in
                        do {
                            try value.insert(db)
                        } catch {
                            DirectLog.error("\(error)")
                        }
                    }
                }
            } catch {
                DirectLog.error("\(error)")
            }
        }
    }

    func deleteFavoriteFood(_ value: FavoriteFood) {
        if let dbQueue = dbQueue {
            do {
                try dbQueue.write { db in
                    do {
                        try FavoriteFood.deleteOne(db, id: value.id)
                    } catch {
                        DirectLog.error("\(error)")
                    }
                }
            } catch {
                DirectLog.error("\(error)")
            }
        }
    }

    func updateFavoriteFood(_ value: FavoriteFood) {
        if let dbQueue = dbQueue {
            do {
                try dbQueue.write { db in
                    do {
                        try value.update(db)
                    } catch {
                        DirectLog.error("\(error)")
                    }
                }
            } catch {
                DirectLog.error("\(error)")
            }
        }
    }

    func reorderFavoriteFoods(_ values: [FavoriteFood]) {
        if let dbQueue = dbQueue {
            do {
                try dbQueue.write { db in
                    for value in values {
                        do {
                            try value.update(db)
                        } catch {
                            DirectLog.error("\(error)")
                        }
                    }
                }
            } catch {
                DirectLog.error("\(error)")
            }
        }
    }

    func updateFavoriteFoodLastUsed(_ value: FavoriteFood) {
        if let dbQueue = dbQueue {
            do {
                try dbQueue.write { db in
                    do {
                        try db.execute(
                            sql: "UPDATE \(FavoriteFood.Table) SET \(FavoriteFood.Columns.lastUsed.name) = ? WHERE \(FavoriteFood.Columns.id.name) = ?",
                            arguments: [Date(), value.id.uuidString.uppercased()]
                        )
                    } catch {
                        DirectLog.error("\(error)")
                    }
                }
            } catch {
                DirectLog.error("\(error)")
            }
        }
    }

    func getFavoriteFoodValues() -> Future<[FavoriteFood], DirectError> {
        return Future { promise in
            if let dbQueue = self.dbQueue {
                dbQueue.asyncRead { asyncDB in
                    do {
                        let db = try asyncDB.get()

                        let result = try FavoriteFood
                            .order(sql: "\(FavoriteFood.Columns.isHypoTreatment.name) DESC, \(FavoriteFood.Columns.sortOrder.name) ASC, \(FavoriteFood.Columns.mealDescription.name) ASC")
                            .fetchAll(db)

                        promise(.success(result))
                    } catch {
                        promise(.failure(.withError(error)))
                    }
                }
            }
        }
    }

    func getRecentMealEntries() -> Future<[MealEntry], DirectError> {
        return Future { promise in
            if let dbQueue = self.dbQueue {
                dbQueue.asyncRead { asyncDB in
                    do {
                        let db = try asyncDB.get()

                        // LIMIT applies AFTER the name-dedupe subquery, so raising it
                        // is monotone: 50 distinct foods instead of 20, same dedupe
                        // semantics (DMNC-1484).
                        let result = try MealEntry.fetchAll(db, sql: """
                            SELECT m.*
                            FROM \(MealEntry.Table) m
                            WHERE m.id = (
                                SELECT m2.id FROM \(MealEntry.Table) m2
                                WHERE m2.mealDescription = m.mealDescription COLLATE NOCASE
                                ORDER BY m2.timestamp DESC
                                LIMIT 1
                            )
                            ORDER BY m.timestamp DESC
                            LIMIT 50
                        """)

                        promise(.success(result))
                    } catch {
                        promise(.failure(.withError(error)))
                    }
                }
            }
        }
    }

    /// Full-history food search (DMNC-1484). `getRecentMealEntries()` only ever
    /// returns the newest N distinct foods; anything older was unreachable from
    /// the sheet's search box. This reaches the whole `MealEntry` table (which is
    /// never pruned) with the same name-dedupe, newest-wins semantics.
    ///
    /// **Matching happens in SWIFT, not SQL, and that is deliberate.** SQLite's
    /// `LIKE` (and `COLLATE NOCASE`) fold ASCII only, so `LIKE '%äpfel%'` does not
    /// match "Äpfel mit Zimt" while the in-memory recents filter
    /// (`localizedCaseInsensitiveContains`) does. Mixing the two produced a
    /// nastier bug than a plain miss: a German food was findable while it sat
    /// inside the recents cap and silently stopped being findable once it aged
    /// out — the same query working, then not. Filtering here with the very same
    /// `localizedCaseInsensitiveContains` call makes the two paths identical by
    /// construction. **Do not "optimise" this back into a `LIKE`** — that
    /// reintroduces the divergence (and the wildcard-escaping burden with it).
    ///
    /// Matching is CONTAINS, not prefix, for the same reason: the in-memory
    /// filter is a contains filter. The plan already accepted a scan here on the
    /// grounds that `MealEntry` is personal-scale (one row per logged meal).
    ///
    /// `limit` bounds *distinct foods returned*, applied after filtering — a
    /// pre-filter `LIMIT` would put old foods back out of reach, which is the
    /// entire bug this exists to fix.
    ///
    /// NO writes inside the `asyncRead` — GRDB deadlock rule applies.
    func searchMealEntries(matching query: String, limit: Int) -> Future<[MealEntry], DirectError> {
        return Future { promise in
            // `guard let`, NOT `if let`: the `if let` form used above never
            // fulfils the promise when `dbQueue` is nil, which would strand the
            // caller's publisher and leave the UI in its loading state forever.
            guard let dbQueue = self.dbQueue else {
                promise(.success([]))
                return
            }

            // Local to matching only — the caller's exact string is what gets
            // echoed back as the result key, never this one.
            let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !needle.isEmpty else {
                promise(.success([]))
                return
            }

            dbQueue.asyncRead { asyncDB in
                do {
                    let db = try asyncDB.get()

                    // One row per distinct food name, newest wins — the same
                    // subquery the recents list uses, unfiltered and unbounded.
                    let candidates = try MealEntry.fetchAll(db, sql: """
                        SELECT m.*
                        FROM \(MealEntry.Table) m
                        WHERE m.id = (
                            SELECT m2.id FROM \(MealEntry.Table) m2
                            WHERE m2.mealDescription = m.mealDescription COLLATE NOCASE
                            ORDER BY m2.timestamp DESC
                            LIMIT 1
                        )
                        ORDER BY m.timestamp DESC
                    """)

                    // Dedupe AGAIN in Swift before taking `limit`: `COLLATE NOCASE`
                    // folds ASCII only, so "MÜSLI" and "Müsli" both survive the SQL
                    // dedupe and would otherwise each burn a slot, yielding fewer
                    // than `limit` genuinely distinct foods.
                    var seen = Set<String>()
                    var result: [MealEntry] = []

                    for candidate in candidates
                        where candidate.mealDescription.localizedCaseInsensitiveContains(needle)
                    {
                        guard seen.insert(candidate.mealDescription.lowercased()).inserted else { continue }
                        result.append(candidate)
                        if result.count == limit { break }
                    }

                    promise(.success(result))
                } catch {
                    promise(.failure(.withError(error)))
                }
            }
        }
    }
}
