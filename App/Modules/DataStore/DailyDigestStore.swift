//
//  DailyDigestStore.swift
//  DOSBTSApp
//

import Combine
import Foundation
import GRDB

// MARK: - DataStore + DailyDigest

extension DataStore {
    func createDailyDigestTable() {
        guard let dbQueue = dbQueue else { return }
        do {
            try dbQueue.write { db in
                try db.create(table: DailyDigest.Table, ifNotExists: true) { t in
                    t.column(DailyDigest.Columns.id.name, .text).primaryKey()
                    t.column(DailyDigest.Columns.date.name, .date).notNull().unique().indexed()
                    t.column(DailyDigest.Columns.tir.name, .double).notNull()
                    t.column(DailyDigest.Columns.tbr.name, .double).notNull()
                    t.column(DailyDigest.Columns.tar.name, .double).notNull()
                    t.column(DailyDigest.Columns.avg.name, .double).notNull()
                    t.column(DailyDigest.Columns.stdev.name, .double).notNull()
                    t.column(DailyDigest.Columns.readings.name, .integer).notNull()
                    t.column(DailyDigest.Columns.lowCount.name, .integer).notNull()
                    t.column(DailyDigest.Columns.highCount.name, .integer).notNull()
                    t.column(DailyDigest.Columns.totalCarbsGrams.name, .double).notNull()
                    t.column(DailyDigest.Columns.totalInsulinUnits.name, .double).notNull()
                    t.column(DailyDigest.Columns.totalExerciseMinutes.name, .double).notNull()
                    t.column(DailyDigest.Columns.mealCount.name, .integer).notNull()
                    t.column(DailyDigest.Columns.insulinCount.name, .integer).notNull()
                    t.column(DailyDigest.Columns.aiInsight.name, .text)
                    t.column(DailyDigest.Columns.generatedAt.name, .date)
                }
            }
        } catch {
            DirectLog.error("\(error)")
        }
    }

    func saveDailyDigest(_ digest: DailyDigest) {
        guard let dbQueue = dbQueue else { return }
        do {
            try dbQueue.write { db in
                try digest.insert(db, onConflict: .replace)
            }
        } catch {
            DirectLog.error("\(error)")
        }
    }

    func getDailyDigest(date: Date) -> Future<DailyDigest?, DirectError> {
        return Future { promise in
            guard let dbQueue = self.dbQueue else {
                promise(.success(nil))
                return
            }

            dbQueue.asyncRead { asyncDB in
                do {
                    let db = try asyncDB.get()
                    let startOfDay = date.startOfDay
                    guard let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) else {
                        promise(.failure(.withMessage("DailyDigestStore: calendar arithmetic failed for \(startOfDay)")))
                        return
                    }

                    let digest = try DailyDigest
                        .filter(Column(DailyDigest.Columns.date.name) >= startOfDay)
                        .filter(Column(DailyDigest.Columns.date.name) < endOfDay)
                        .fetchOne(db)

                    promise(.success(digest))
                } catch {
                    promise(.failure(.withError(error)))
                }
            }
        }
    }

    func getLast7Digests() -> Future<[DailyDigest], DirectError> {
        return Future { promise in
            guard let dbQueue = self.dbQueue else {
                promise(.success([]))
                return
            }

            dbQueue.asyncRead { asyncDB in
                do {
                    let db = try asyncDB.get()
                    let digests = try DailyDigest
                        .order(Column(DailyDigest.Columns.date.name).desc)
                        .limit(7)
                        .fetchAll(db)
                    promise(.success(digests))
                } catch {
                    promise(.failure(.withError(error)))
                }
            }
        }
    }

    func updateDailyDigestInsight(date: Date, insight: String) {
        guard let dbQueue = dbQueue else { return }
        do {
            try dbQueue.write { db in
                let startOfDay = date.startOfDay
                guard let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) else {
                    DirectLog.error("DailyDigestStore.updateDailyDigestInsight: calendar arithmetic failed for \(startOfDay)")
                    return
                }

                try db.execute(
                    sql: """
                        UPDATE \(DailyDigest.Table)
                        SET \(DailyDigest.Columns.aiInsight.name) = ?,
                            \(DailyDigest.Columns.generatedAt.name) = ?
                        WHERE \(DailyDigest.Columns.date.name) >= ? AND \(DailyDigest.Columns.date.name) < ?
                    """,
                    arguments: [insight, Date(), startOfDay, endOfDay]
                )
            }
        } catch {
            DirectLog.error("\(error)")
        }
    }

    /// Compute a daily digest by querying glucose, meals, insulin, and exercise for a given day.
    /// Runs all queries in a single synchronous read to avoid Combine chaining complexity.
    func computeDailyDigest(date: Date, alarmLow: Int, alarmHigh: Int) -> Future<DailyDigest, DirectError> {
        return Future { promise in
            guard let dbQueue = self.dbQueue else {
                // Return empty digest rather than hanging
                let empty = DailyDigest(date: date, tir: 0, tbr: 0, tar: 0, avg: 0, stdev: 0, readings: 0, lowCount: 0, highCount: 0, totalCarbsGrams: 0, totalInsulinUnits: 0, totalExerciseMinutes: 0, mealCount: 0, insulinCount: 0)
                promise(.success(empty))
                return
            }

            dbQueue.asyncRead { asyncDB in
                do {
                    let db = try asyncDB.get()
                    let startOfDay = date.startOfDay
                    guard let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) else {
                        promise(.failure(.withMessage("DailyDigestStore: calendar arithmetic failed for \(startOfDay)")))
                        return
                    }

                    // Glucose readings for the day
                    let glucoseReadings = try SensorGlucose
                        .filter(Column(SensorGlucose.Columns.timestamp.name) >= startOfDay)
                        .filter(Column(SensorGlucose.Columns.timestamp.name) < endOfDay)
                        .order(Column(SensorGlucose.Columns.timestamp.name))
                        .fetchAll(db)

                    // Meals
                    let meals = try MealEntry
                        .filter(Column(MealEntry.Columns.timestamp.name) >= startOfDay)
                        .filter(Column(MealEntry.Columns.timestamp.name) < endOfDay)
                        .fetchAll(db)

                    // Insulin
                    let insulin = try InsulinDelivery
                        .filter(Column(InsulinDelivery.Columns.starts.name) >= startOfDay)
                        .filter(Column(InsulinDelivery.Columns.starts.name) < endOfDay)
                        .fetchAll(db)

                    // Exercise
                    let exercise = try ExerciseEntry
                        .filter(Column(ExerciseEntry.Columns.startTime.name) >= startOfDay)
                        .filter(Column(ExerciseEntry.Columns.startTime.name) < endOfDay)
                        .fetchAll(db)

                    // Compute stats
                    let readingsCount = glucoseReadings.count
                    var tir = 0.0, tbr = 0.0, tar = 0.0, avg = 0.0, stdev = 0.0
                    var lowCount = 0, highCount = 0

                    if readingsCount > 0 {
                        let values = glucoseReadings.map { $0.glucoseValue }
                        lowCount = values.filter { $0 < alarmLow }.count
                        highCount = values.filter { $0 > alarmHigh }.count
                        let inRange = readingsCount - lowCount - highCount

                        tir = Double(inRange) / Double(readingsCount) * 100.0
                        tbr = Double(lowCount) / Double(readingsCount) * 100.0
                        tar = Double(highCount) / Double(readingsCount) * 100.0

                        let sum = values.reduce(0, +)
                        avg = Double(sum) / Double(readingsCount)

                        let sumOfSquares = values.map { pow(Double($0) - avg, 2.0) }.reduce(0, +)
                        stdev = readingsCount > 1 ? sqrt(sumOfSquares / Double(readingsCount - 1)) : 0
                    }

                    let totalCarbs = meals.compactMap(\.carbsGrams).reduce(0, +)
                    let totalInsulin = insulin.map(\.units).reduce(0, +)
                    let totalExercise = exercise.map(\.durationMinutes).reduce(0, +)

                    let digest = DailyDigest(
                        date: startOfDay,
                        tir: tir,
                        tbr: tbr,
                        tar: tar,
                        avg: avg,
                        stdev: stdev,
                        readings: readingsCount,
                        lowCount: lowCount,
                        highCount: highCount,
                        totalCarbsGrams: totalCarbs,
                        totalInsulinUnits: totalInsulin,
                        totalExerciseMinutes: totalExercise,
                        mealCount: meals.count,
                        insulinCount: insulin.count
                    )

                    promise(.success(digest))
                } catch {
                    promise(.failure(.withError(error)))
                }
            }
        }
    }

    /// Get events (meals, insulin, exercise) for a given day for the timeline and AI prompt.
    func getDailyEvents(date: Date) -> Future<DailyDigestEvents, DirectError> {
        return Future { promise in
            guard let dbQueue = self.dbQueue else {
                promise(.success(DailyDigestEvents(meals: [], insulin: [], exercise: [])))
                return
            }

            dbQueue.asyncRead { asyncDB in
                do {
                    let db = try asyncDB.get()
                    let startOfDay = date.startOfDay
                    guard let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) else {
                        promise(.failure(.withMessage("DailyDigestStore: calendar arithmetic failed for \(startOfDay)")))
                        return
                    }

                    let meals = try MealEntry
                        .filter(Column(MealEntry.Columns.timestamp.name) >= startOfDay)
                        .filter(Column(MealEntry.Columns.timestamp.name) < endOfDay)
                        .order(Column(MealEntry.Columns.timestamp.name))
                        .fetchAll(db)

                    let insulin = try InsulinDelivery
                        .filter(Column(InsulinDelivery.Columns.starts.name) >= startOfDay)
                        .filter(Column(InsulinDelivery.Columns.starts.name) < endOfDay)
                        .order(Column(InsulinDelivery.Columns.starts.name))
                        .fetchAll(db)

                    let exercise = try ExerciseEntry
                        .filter(Column(ExerciseEntry.Columns.startTime.name) >= startOfDay)
                        .filter(Column(ExerciseEntry.Columns.startTime.name) < endOfDay)
                        .order(Column(ExerciseEntry.Columns.startTime.name))
                        .fetchAll(db)

                    let notes = try JournalNote
                        .filter(Column(JournalNote.Columns.timestamp.name) >= startOfDay)
                        .filter(Column(JournalNote.Columns.timestamp.name) < endOfDay)
                        .order(Column(JournalNote.Columns.timestamp.name))
                        .fetchAll(db)

                    promise(.success(DailyDigestEvents(meals: meals, insulin: insulin, exercise: exercise, notes: notes)))
                } catch {
                    promise(.failure(.withError(error)))
                }
            }
        }
    }

    /// Sample glucose readings at 30-minute intervals for AI prompt context.
    func getGlucoseSamples(date: Date) -> Future<[(Date, Int)], DirectError> {
        return Future { promise in
            guard let dbQueue = self.dbQueue else {
                promise(.success([]))
                return
            }

            dbQueue.asyncRead { asyncDB in
                do {
                    let db = try asyncDB.get()
                    let startOfDay = date.startOfDay
                    guard let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) else {
                        promise(.failure(.withMessage("DailyDigestStore: calendar arithmetic failed for \(startOfDay)")))
                        return
                    }

                    let readings = try SensorGlucose
                        .filter(Column(SensorGlucose.Columns.timestamp.name) >= startOfDay)
                        .filter(Column(SensorGlucose.Columns.timestamp.name) < endOfDay)
                        .order(Column(SensorGlucose.Columns.timestamp.name))
                        .fetchAll(db)

                    // Sample at 30-min intervals
                    var samples: [(Date, Int)] = []
                    var nextSampleTime = startOfDay
                    let interval: TimeInterval = 30 * 60

                    for reading in readings {
                        if reading.timestamp >= nextSampleTime {
                            samples.append((reading.timestamp, reading.glucoseValue))
                            nextSampleTime = reading.timestamp.addingTimeInterval(interval)
                        }
                    }

                    promise(.success(samples))
                } catch {
                    promise(.failure(.withError(error)))
                }
            }
        }
    }
}

