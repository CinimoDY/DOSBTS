//
//  FoodCorrectionStore.swift
//  DOSBTSApp
//
//  Single middleware handling:
//  - FoodCorrection table (AI correction log)
//  - PersonalFood table (AI-observed food dictionary, auto-populated from corrections)
//  Cross-middleware: .saveMealWithCorrections writes corrections + upserts dictionary,
//  then emits .addMealEntry to chain into mealEntryStoreMiddleware.

import Combine
import Foundation
import GRDB

func foodCorrectionStoreMiddleware() -> Middleware<DirectState, DirectAction> {
    return { state, action, _ in
        switch action {
        case .startup:
            DataStore.shared.createFoodCorrectionTable()
            DataStore.shared.createPersonalFoodTable()
            DataStore.shared.prunePersonalFoodHistory()

            return Publishers.MergeMany([
                Just(DirectAction.loadPersonalFoods)
                    .setFailureType(to: DirectError.self),
                Just(DirectAction.loadScoredPersonalFoods)
                    .setFailureType(to: DirectError.self),
                Just(DirectAction.loadRecentFoodCorrections)
                    .setFailureType(to: DirectError.self),
            ]).eraseToAnyPublisher()

        case .saveMealWithCorrections(meal: let meal, corrections: let corrections):
            // Atomic write: corrections + PersonalFood upserts in one transaction.
            // Then emit .addMealEntry to chain into mealEntryStoreMiddleware.
            if !corrections.isEmpty {
                DataStore.shared.insertFoodCorrectionsAndUpsertPersonalFoods(corrections, analysisSessionId: meal.analysisSessionId)
            }

            // Cross-middleware: .addMealEntry is also handled by mealEntryStoreMiddleware
            // (DB write) and favoriteFoodStoreMiddleware (recents update)
            return Publishers.MergeMany([
                Just(DirectAction.addMealEntry(mealEntryValues: [meal]))
                    .setFailureType(to: DirectError.self),
                Just(DirectAction.loadPersonalFoods)
                    .setFailureType(to: DirectError.self),
                Just(DirectAction.loadScoredPersonalFoods)
                    .setFailureType(to: DirectError.self),
                Just(DirectAction.loadRecentFoodCorrections)
                    .setFailureType(to: DirectError.self),
            ]).eraseToAnyPublisher()

        case .loadPersonalFoods:
            guard state.appState == .active else {
                return Empty().eraseToAnyPublisher()
            }

            return DataStore.shared.getPersonalFoods().map { personalFoods in
                DirectAction.setPersonalFoods(personalFoods: personalFoods)
            }.eraseToAnyPublisher()

        case .loadScoredPersonalFoods:
            guard state.appState == .active else {
                return Empty().eraseToAnyPublisher()
            }

            return DataStore.shared.getScoredPersonalFoods().map { foods in
                DirectAction.setScoredPersonalFoods(scoredPersonalFoods: foods)
            }.eraseToAnyPublisher()

        case .loadRecentFoodCorrections:
            guard state.appState == .active else {
                return Empty().eraseToAnyPublisher()
            }

            return DataStore.shared.getRecentFoodCorrections().map { corrections in
                DirectAction.setRecentFoodCorrections(recentFoodCorrections: corrections)
            }.eraseToAnyPublisher()

        case .setAppState(appState: let appState):
            guard appState == .active else {
                return Empty().eraseToAnyPublisher()
            }

            return Publishers.MergeMany([
                Just(DirectAction.loadPersonalFoods)
                    .setFailureType(to: DirectError.self),
                Just(DirectAction.loadScoredPersonalFoods)
                    .setFailureType(to: DirectError.self),
                Just(DirectAction.loadRecentFoodCorrections)
                    .setFailureType(to: DirectError.self),
            ]).eraseToAnyPublisher()

        default:
            break
        }

        return Empty().eraseToAnyPublisher()
    }
}

// MARK: - DataStore FoodCorrection + PersonalFood extensions

private extension DataStore {
    func createFoodCorrectionTable() {
        if let dbQueue = dbQueue {
            do {
                try dbQueue.write { db in
                    try db.create(table: FoodCorrection.Table, ifNotExists: true) { t in
                        t.column(FoodCorrection.Columns.id.name, .text)
                            .primaryKey()
                        t.column(FoodCorrection.Columns.timestamp.name, .date)
                            .notNull()
                            .indexed()
                        t.column(FoodCorrection.Columns.correctionType.name, .text)
                            .notNull()
                        t.column(FoodCorrection.Columns.originalName.name, .text)
                        t.column(FoodCorrection.Columns.correctedName.name, .text)
                        t.column(FoodCorrection.Columns.originalCarbsG.name, .double)
                        t.column(FoodCorrection.Columns.correctedCarbsG.name, .double)
                    }
                }
            } catch {
                DirectLog.error("\(error)")
            }
        }
    }

    func createPersonalFoodTable() {
        if let dbQueue = dbQueue {
            do {
                try dbQueue.write { db in
                    try db.create(table: PersonalFood.Table, ifNotExists: true) { t in
                        t.column(PersonalFood.Columns.id.name, .text)
                            .primaryKey()
                        t.column(PersonalFood.Columns.name.name, .text)
                            .notNull()
                        t.column(PersonalFood.Columns.carbsG.name, .double)
                            .notNull()
                        t.column(PersonalFood.Columns.lastUsed.name, .date)
                            .notNull()
                            .indexed()
                    }

                    // Case-insensitive unique index on name
                    try db.execute(sql: """
                        CREATE UNIQUE INDEX IF NOT EXISTS PersonalFood_name_nocase
                        ON \(PersonalFood.Table)(name COLLATE NOCASE)
                    """)
                }
            } catch {
                DirectLog.error("\(error)")
            }

            var migrator = DatabaseMigrator()
            migrator.registerMigration("Add analysisSessionId to PersonalFood") { db in
                try db.alter(table: PersonalFood.Table) { t in
                    t.add(column: PersonalFood.Columns.analysisSessionId.name, .text)
                }
            }

            migrator.registerMigration("Add glycemic scoring to PersonalFood") { db in
                try db.alter(table: PersonalFood.Table) { t in
                    t.add(column: PersonalFood.Columns.avgDeltaMgDL.name, .double)
                    t.add(column: PersonalFood.Columns.observationCount.name, .integer).defaults(to: 0)
                    t.add(column: PersonalFood.Columns.lastScoredDate.name, .date)
                }
            }

            do {
                try migrator.migrate(dbQueue)
            } catch {
                DirectLog.error("\(error)")
            }
        }
    }

    func prunePersonalFoodHistory() {
        if let dbQueue = dbQueue {
            do {
                try dbQueue.write { db in
                    // Step 1: age prune (>90 days unused)
                    try db.execute(sql: """
                        DELETE FROM \(PersonalFood.Table)
                        WHERE \(PersonalFood.Columns.lastUsed.name) < datetime('now', '-90 days')
                    """)

                    // Step 2: cap prune (max 200 entries)
                    let remaining = try PersonalFood.fetchCount(db)
                    if remaining > 200 {
                        try db.execute(sql: """
                            DELETE FROM \(PersonalFood.Table)
                            WHERE \(PersonalFood.Columns.id.name) IN (
                                SELECT \(PersonalFood.Columns.id.name)
                                FROM \(PersonalFood.Table)
                                ORDER BY \(PersonalFood.Columns.lastUsed.name) ASC
                                LIMIT ?
                            )
                        """, arguments: [remaining - 200])
                    }
                }
            } catch {
                DirectLog.error("\(error)")
            }
        }
    }

    func insertFoodCorrectionsAndUpsertPersonalFoods(_ corrections: [FoodCorrection], analysisSessionId: UUID? = nil) {
        if let dbQueue = dbQueue {
            do {
                try dbQueue.write { db in
                    // Phase 1: Insert all corrections
                    for correction in corrections {
                        do {
                            try correction.insert(db)
                        } catch {
                            DirectLog.error("\(error)")
                        }
                    }

                    // Phase 2: Upsert PersonalFood from corrections
                    for correction in corrections {
                        let foodName: String?
                        let carbsG: Double?

                        switch correction.correctionType {
                        case .nameChange:
                            foodName = correction.correctedName
                            carbsG = correction.correctedCarbsG ?? correction.originalCarbsG
                        case .carbChange:
                            foodName = correction.correctedName ?? correction.originalName
                            carbsG = correction.correctedCarbsG
                        case .added:
                            foodName = correction.correctedName
                            carbsG = correction.correctedCarbsG
                        case .deleted:
                            continue // No dictionary entry for hallucinated items
                        }

                        guard let name = foodName, !name.isEmpty, let carbs = carbsG else { continue }

                        // Manual upsert: preserves UUID on update
                        do {
                            let existing = try PersonalFood
                                .filter(sql: "name = ? COLLATE NOCASE", arguments: [name])
                                .fetchOne(db)

                            if let existing = existing {
                                try db.execute(
                                    sql: """
                                        UPDATE \(PersonalFood.Table)
                                        SET \(PersonalFood.Columns.carbsG.name) = ?,
                                            \(PersonalFood.Columns.lastUsed.name) = ?
                                        WHERE \(PersonalFood.Columns.id.name) = ?
                                    """,
                                    arguments: [carbs, Date(), existing.id.uuidString.uppercased()]
                                )
                            } else {
                                try PersonalFood(name: name, carbsG: carbs, analysisSessionId: analysisSessionId).insert(db)
                            }
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

    func getScoredPersonalFoods() -> Future<[PersonalFood], DirectError> {
        return Future { promise in
            if let dbQueue = self.dbQueue {
                dbQueue.asyncRead { asyncDB in
                    do {
                        let db = try asyncDB.get()

                        let result = try PersonalFood
                            .filter(sql: "\(PersonalFood.Columns.avgDeltaMgDL.name) IS NOT NULL")
                            .order(Column(PersonalFood.Columns.avgDeltaMgDL.name).desc)
                            .fetchAll(db)

                        promise(.success(result))
                    } catch {
                        promise(.failure(.withError(error)))
                    }
                }
            } else {
                promise(.success([]))
            }
        }
    }

    func getPersonalFoods() -> Future<[PersonalFood], DirectError> {
        return Future { promise in
            if let dbQueue = self.dbQueue {
                dbQueue.asyncRead { asyncDB in
                    do {
                        let db = try asyncDB.get()

                        let result = try PersonalFood
                            .order(Column(PersonalFood.Columns.lastUsed.name).desc)
                            .limit(12)
                            .fetchAll(db)

                        promise(.success(result))
                    } catch {
                        promise(.failure(.withError(error)))
                    }
                }
            } else {
                promise(.success([]))
            }
        }
    }

    func getRecentFoodCorrections() -> Future<[FoodCorrection], DirectError> {
        return Future { promise in
            if let dbQueue = self.dbQueue {
                dbQueue.asyncRead { asyncDB in
                    do {
                        let db = try asyncDB.get()

                        let result = try FoodCorrection
                            .filter(sql: "\(FoodCorrection.Columns.timestamp.name) >= datetime('now', '-30 days')")
                            .order(Column(FoodCorrection.Columns.timestamp.name).desc)
                            .limit(7)
                            .fetchAll(db)

                        promise(.success(result))
                    } catch {
                        promise(.failure(.withError(error)))
                    }
                }
            } else {
                promise(.success([]))
            }
        }
    }
}
