//
//  MealImpactStore.swift
//  DOSBTSApp
//

import Combine
import Foundation
import GRDB

func mealImpactStoreMiddleware() -> Middleware<DirectState, DirectAction> {
    return { state, action, _ in
        switch action {
        case .startup:
            DataStore.shared.createMealImpactTable()
            // Table creation only — loadScoredMealEntryIds is triggered by .setAppState(.active)
            return Empty().eraseToAnyPublisher()

        case .setAppState(appState: let appState):
            guard appState == .active else {
                return Empty().eraseToAnyPublisher()
            }
            // Retroactive scan: compute impacts for meals that have completed their 2hr window
            return DataStore.shared.computePendingMealImpacts().flatMap { _ in
                Publishers.MergeMany([
                    Just(DirectAction.loadScoredMealEntryIds)
                        .setFailureType(to: DirectError.self),
                    Just(DirectAction.loadScoredPersonalFoods)
                        .setFailureType(to: DirectError.self),
                ]).eraseToAnyPublisher()
            }.eraseToAnyPublisher()

        // Cross-middleware: .addSensorGlucose is also handled by SensorConnector,
        // GlucoseNotification, IOBMiddleware, WidgetCenter, and others
        case .addSensorGlucose:
            // Incremental: check if any meals just completed their 2hr window
            return DataStore.shared.computePendingMealImpacts().flatMap { _ in
                Publishers.MergeMany([
                    Just(DirectAction.loadScoredMealEntryIds)
                        .setFailureType(to: DirectError.self),
                    Just(DirectAction.loadScoredPersonalFoods)
                        .setFailureType(to: DirectError.self),
                ]).eraseToAnyPublisher()
            }.eraseToAnyPublisher()

        // Cross-middleware: MealStore also handles .deleteMealEntry
        // Cascade delete: remove MealImpact when meal is deleted
        case .deleteMealEntry(mealEntry: let mealEntry):
            DataStore.shared.deleteMealImpact(byMealEntryId: mealEntry.id)
            return Just(DirectAction.loadScoredMealEntryIds)
                .setFailureType(to: DirectError.self)
                .eraseToAnyPublisher()

        case .loadScoredMealEntryIds:
            guard state.appState == .active else {
                return Empty().eraseToAnyPublisher()
            }
            return DataStore.shared.getScoredMealEntryIds().map { ids in
                DirectAction.setScoredMealEntryIds(scoredMealEntryIds: ids)
            }.eraseToAnyPublisher()

        default:
            break
        }

        return Empty().eraseToAnyPublisher()
    }
}

// MARK: - DataStore + MealImpact

private extension DataStore {
    func createMealImpactTable() {
        guard let dbQueue = dbQueue else { return }
        do {
            try dbQueue.write { db in
                try db.create(table: MealImpact.Table, ifNotExists: true) { t in
                    t.column(MealImpact.Columns.id.name, .text).primaryKey()
                    t.column(MealImpact.Columns.mealEntryId.name, .text).notNull().unique()
                    t.column(MealImpact.Columns.baselineGlucose.name, .integer)
                    t.column(MealImpact.Columns.peakGlucose.name, .integer).notNull()
                    t.column(MealImpact.Columns.deltaMgDL.name, .integer).notNull()
                    t.column(MealImpact.Columns.timeToPeakMinutes.name, .integer).notNull()
                    t.column(MealImpact.Columns.isClean.name, .boolean).notNull()
                    t.column(MealImpact.Columns.timestamp.name, .date).notNull().indexed()
                }
            }
        } catch {
            DirectLog.error("\(error)")
        }
    }

    func computePendingMealImpacts() -> Future<Void, DirectError> {
        return Future { promise in
            guard let dbQueue = self.dbQueue else {
                promise(.success(()))
                return
            }

            dbQueue.asyncWrite({ db in
                // Find meals whose 2hr window has elapsed and that don't have a MealImpact yet
                // Lower bound (30 days) prevents unbounded historical scans on every glucose reading
                let twoHoursAgo = Date().addingTimeInterval(-2 * 60 * 60)
                let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)

                let pendingMeals = try MealEntry
                    .filter(Column(MealEntry.Columns.timestamp.name) >= thirtyDaysAgo)
                    .filter(Column(MealEntry.Columns.timestamp.name) <= twoHoursAgo)
                    .filter(sql: """
                        \(MealEntry.Columns.id.name) NOT IN (
                            SELECT \(MealImpact.Columns.mealEntryId.name) FROM \(MealImpact.Table)
                        )
                    """)
                    .fetchAll(db)

                for meal in pendingMeals {
                    // Per-meal savepoint: a failure on one meal doesn't roll back others
                    do { try db.inSavepoint {
                    // Get glucose readings in the 2hr window after meal
                    let windowEnd = meal.timestamp.addingTimeInterval(2 * 60 * 60)
                    let glucoseReadings = try SensorGlucose
                        .filter(Column(SensorGlucose.Columns.timestamp.name) >= meal.timestamp)
                        .filter(Column(SensorGlucose.Columns.timestamp.name) <= windowEnd)
                        .order(Column(SensorGlucose.Columns.timestamp.name))
                        .fetchAll(db)

                    // Need at least 4 readings (R13 threshold)
                    guard glucoseReadings.count >= 4 else { return .rollback }

                    // Find baseline: closest reading before meal within 15 min
                    let baselineStart = meal.timestamp.addingTimeInterval(-15 * 60)
                    let baselineReading = try SensorGlucose
                        .filter(Column(SensorGlucose.Columns.timestamp.name) >= baselineStart)
                        .filter(Column(SensorGlucose.Columns.timestamp.name) < meal.timestamp)
                        .order(Column(SensorGlucose.Columns.timestamp.name).desc)
                        .fetchOne(db)

                    let baselineGlucose = baselineReading?.glucoseValue
                    let referenceGlucose: Int
                    if let baseline = baselineGlucose {
                        referenceGlucose = baseline
                    } else {
                        referenceGlucose = glucoseReadings[0].glucoseValue
                    }

                    // Find peak glucose in the window
                    guard let peakReading = glucoseReadings.max(by: { $0.glucoseValue < $1.glucoseValue }) else { return .rollback }
                    let peakGlucose = peakReading.glucoseValue
                    let deltaMgDL = peakGlucose - referenceGlucose
                    let timeToPeakMinutes = Int(peakReading.timestamp.timeIntervalSince(meal.timestamp) / 60)

                    // Confounder detection
                    var isClean = true

                    // Check for correction boluses in window
                    // InsulinType is Codable (not RawRepresentable), so fetch all insulin in window and filter in Swift
                    let insulinInWindow = try InsulinDelivery
                        .filter(Column(InsulinDelivery.Columns.starts.name) >= meal.timestamp)
                        .filter(Column(InsulinDelivery.Columns.starts.name) <= windowEnd)
                        .fetchAll(db)
                    let hasCorrectionBolus = insulinInWindow.contains { $0.type == .correctionBolus }
                    if hasCorrectionBolus { isClean = false }

                    // Check for exercise overlapping window
                    let exerciseOverlap = try ExerciseEntry
                        .filter(Column(ExerciseEntry.Columns.startTime.name) <= windowEnd)
                        .filter(Column(ExerciseEntry.Columns.endTime.name) >= meal.timestamp)
                        .fetchCount(db)
                    if exerciseOverlap > 0 { isClean = false }

                    // Check for stacked meals (another meal within 2hr window)
                    let stackedMeals = try MealEntry
                        .filter(Column(MealEntry.Columns.id.name) != meal.id.uuidString.uppercased())
                        .filter(Column(MealEntry.Columns.timestamp.name) >= meal.timestamp)
                        .filter(Column(MealEntry.Columns.timestamp.name) <= windowEnd)
                        .fetchCount(db)
                    if stackedMeals > 0 { isClean = false }

                    let impact = MealImpact(
                        mealEntryId: meal.id,
                        baselineGlucose: baselineGlucose,
                        peakGlucose: peakGlucose,
                        deltaMgDL: deltaMgDL,
                        timeToPeakMinutes: timeToPeakMinutes,
                        isClean: isClean,
                        timestamp: meal.timestamp
                    )

                    // insertOrIgnore prevents duplicates (UNIQUE on mealEntryId)
                    try impact.insert(db, onConflict: .ignore)

                    // PersonalFood glycemic scoring: update rolling average for clean observations
                    if isClean, let sessionId = meal.analysisSessionId {
                        let personalFoods = try PersonalFood
                            .filter(Column(PersonalFood.Columns.analysisSessionId.name) == sessionId.uuidString.uppercased())
                            .fetchAll(db)

                        for food in personalFoods {
                            let oldAvg = food.avgDeltaMgDL ?? 0.0
                            let oldCount = food.observationCount
                            let newAvg = ((oldAvg * Double(oldCount)) + Double(deltaMgDL)) / Double(oldCount + 1)

                            try db.execute(
                                sql: """
                                    UPDATE \(PersonalFood.Table)
                                    SET \(PersonalFood.Columns.avgDeltaMgDL.name) = ?,
                                        \(PersonalFood.Columns.observationCount.name) = ?,
                                        \(PersonalFood.Columns.lastScoredDate.name) = ?
                                    WHERE \(PersonalFood.Columns.id.name) = ?
                                """,
                                arguments: [newAvg, oldCount + 1, Date(), food.id.uuidString.uppercased()]
                            )
                        }
                    }
                    return .commit
                    } } catch { DirectLog.error("MealImpact computation skipped for meal \(meal.id): \(error)") }
                }
            }, completion: { _, result in
                switch result {
                case .success:
                    promise(.success(()))
                case .failure(let error):
                    DirectLog.error("MealImpact computation failed: \(error)")
                    promise(.success(())) // Silent failure — don't block glucose processing
                }
            })
        }
    }

    func deleteMealImpact(byMealEntryId mealEntryId: UUID) {
        guard let dbQueue = dbQueue else { return }
        do {
            try dbQueue.write { db in
                try db.execute(
                    sql: "DELETE FROM \(MealImpact.Table) WHERE \(MealImpact.Columns.mealEntryId.name) = ?",
                    arguments: [mealEntryId.uuidString.uppercased()]
                )
            }
        } catch {
            DirectLog.error("\(error)")
        }
    }

    func getScoredMealEntryIds() -> Future<Set<UUID>, DirectError> {
        return Future { promise in
            guard let dbQueue = self.dbQueue else {
                promise(.success(Set()))
                return
            }

            dbQueue.asyncRead { asyncDB in
                do {
                    let db = try asyncDB.get()
                    let rows = try Row.fetchAll(db,
                        sql: "SELECT \(MealImpact.Columns.mealEntryId.name) FROM \(MealImpact.Table)"
                    )
                    let ids = Set(rows.compactMap { row -> UUID? in
                        guard let uuidString: String = row[MealImpact.Columns.mealEntryId.name] else { return nil }
                        return UUID(uuidString: uuidString)
                    })
                    promise(.success(ids))
                } catch {
                    promise(.failure(.withError(error)))
                }
            }
        }
    }
}
