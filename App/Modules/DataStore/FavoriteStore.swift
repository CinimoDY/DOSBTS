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

        case .loadFavoriteFoodValues:
            guard state.appState == .active else {
                return Empty().eraseToAnyPublisher()
            }

            return DataStore.shared.getFavoriteFoodValues().map { favoriteFoodValues in
                DirectAction.setFavoriteFoodValues(favoriteFoodValues: favoriteFoodValues)
            }.eraseToAnyPublisher()

        case .logFavoriteFood(favoriteFood: let favoriteFood):
            let mealEntry = MealEntry(
                timestamp: Date(),
                mealDescription: favoriteFood.mealDescription,
                carbsGrams: favoriteFood.carbsGrams,
                proteinGrams: favoriteFood.proteinGrams,
                fatGrams: favoriteFood.fatGrams,
                calories: favoriteFood.calories,
                fiberGrams: favoriteFood.fiberGrams
            )

            DataStore.shared.updateFavoriteFoodLastUsed(favoriteFood)

            return Just(DirectAction.addMealEntry(mealEntryValues: [mealEntry]))
                .setFailureType(to: DirectError.self)
                .eraseToAnyPublisher()

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

            migrator.registerMigration("Add index on MealEntry mealDescription") { db in
                try db.execute(sql: "CREATE INDEX IF NOT EXISTS MealEntry_mealDescription ON MealEntry(mealDescription COLLATE NOCASE)")
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

                        let result = try MealEntry.fetchAll(db, sql: """
                            SELECT m.*
                            FROM \(MealEntry.Table) m
                            INNER JOIN (
                                SELECT mealDescription, MAX(timestamp) as maxTimestamp
                                FROM \(MealEntry.Table)
                                GROUP BY mealDescription COLLATE NOCASE
                            ) latest ON m.mealDescription = latest.mealDescription COLLATE NOCASE
                                   AND m.timestamp = latest.maxTimestamp
                            ORDER BY m.timestamp DESC
                            LIMIT 20
                        """)

                        promise(.success(result))
                    } catch {
                        promise(.failure(.withError(error)))
                    }
                }
            }
        }
    }
}
