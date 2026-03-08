//
//  ExerciseStore.swift
//  DOSBTSApp
//

import Combine
import Foundation
import GRDB

func exerciseEntryStoreMiddleware() -> Middleware<DirectState, DirectAction> {
    return { state, action, _ in
        switch action {
        case .startup:
            DataStore.shared.createExerciseEntryTable()

            return DataStore.shared.getFirstExerciseEntryDate().map { minSelectedDate in
                DirectAction.setMinSelectedDate(minSelectedDate: minSelectedDate)
            }.eraseToAnyPublisher()

        case .addExerciseEntry(exerciseEntryValues: let exerciseEntryValues):
            guard !exerciseEntryValues.isEmpty else {
                return Empty().eraseToAnyPublisher()
            }

            DataStore.shared.insertExerciseEntry(exerciseEntryValues)

            return Just(DirectAction.loadExerciseEntryValues)
                .setFailureType(to: DirectError.self)
                .eraseToAnyPublisher()

        case .deleteExerciseEntry(exerciseEntry: let exerciseEntry):
            DataStore.shared.deleteExerciseEntry(exerciseEntry)

            return Just(DirectAction.loadExerciseEntryValues)
                .setFailureType(to: DirectError.self)
                .eraseToAnyPublisher()

        case .setSelectedDate(selectedDate: _):
            return Just(DirectAction.loadExerciseEntryValues)
                .setFailureType(to: DirectError.self)
                .eraseToAnyPublisher()

        case .loadExerciseEntryValues:
            guard state.appState == .active else {
                return Empty().eraseToAnyPublisher()
            }

            return DataStore.shared.getExerciseEntryValues(selectedDate: state.selectedDate).map { exerciseEntryValues in
                DirectAction.setExerciseEntryValues(exerciseEntryValues: exerciseEntryValues)
            }.eraseToAnyPublisher()

        case .setAppState(appState: let appState):
            guard appState == .active else {
                return Empty().eraseToAnyPublisher()
            }

            return Just(DirectAction.loadExerciseEntryValues)
                .setFailureType(to: DirectError.self)
                .eraseToAnyPublisher()

        default:
            break
        }

        return Empty().eraseToAnyPublisher()
    }
}

private extension DataStore {
    func createExerciseEntryTable() {
        if let dbQueue = dbQueue {
            do {
                try dbQueue.write { db in
                    try db.create(table: ExerciseEntry.Table, ifNotExists: true) { t in
                        t.column(ExerciseEntry.Columns.id.name, .text)
                            .primaryKey()
                        t.column(ExerciseEntry.Columns.startTime.name, .date)
                            .notNull()
                            .indexed()
                        t.column(ExerciseEntry.Columns.endTime.name, .date)
                            .notNull()
                        t.column(ExerciseEntry.Columns.activityType.name, .text)
                            .notNull()
                        t.column(ExerciseEntry.Columns.durationMinutes.name, .double)
                            .notNull()
                        t.column(ExerciseEntry.Columns.activeCalories.name, .double)
                        t.column(ExerciseEntry.Columns.source.name, .text)
                        t.column(ExerciseEntry.Columns.timegroup.name, .date)
                            .notNull()
                            .indexed()
                    }
                }
            } catch {
                DirectLog.error("\(error)")
            }
        }
    }

    func deleteAllExerciseEntry() {
        if let dbQueue = dbQueue {
            do {
                try dbQueue.write { db in
                    do {
                        try ExerciseEntry.deleteAll(db)
                    } catch {
                        DirectLog.error("\(error)")
                    }
                }
            } catch {
                DirectLog.error("\(error)")
            }
        }
    }

    func deleteExerciseEntry(_ value: ExerciseEntry) {
        if let dbQueue = dbQueue {
            do {
                try dbQueue.write { db in
                    do {
                        try ExerciseEntry.deleteOne(db, id: value.id)
                    } catch {
                        DirectLog.error("\(error)")
                    }
                }
            } catch {
                DirectLog.error("\(error)")
            }
        }
    }

    func insertExerciseEntry(_ values: [ExerciseEntry]) {
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

    func getFirstExerciseEntryDate() -> Future<Date, DirectError> {
        return Future { promise in
            if let dbQueue = self.dbQueue {
                dbQueue.asyncRead { asyncDB in
                    do {
                        let db = try asyncDB.get()

                        if let date = try Date.fetchOne(db, sql: "SELECT MIN(startTime) FROM \(ExerciseEntry.Table)") {
                            promise(.success(date))
                        } else {
                            promise(.success(Date()))
                        }
                    } catch {
                        promise(.failure(.withError(error)))
                    }
                }
            }
        }
    }

    func getExerciseEntryValues(selectedDate: Date? = nil) -> Future<[ExerciseEntry], DirectError> {
        return Future { promise in
            if let dbQueue = self.dbQueue {
                dbQueue.asyncRead { asyncDB in
                    do {
                        let db = try asyncDB.get()

                        if let selectedDate = selectedDate, let nextDate = Calendar.current.date(byAdding: .day, value: +1, to: selectedDate) {
                            let result = try ExerciseEntry
                                .filter(Column(ExerciseEntry.Columns.startTime.name) >= selectedDate.startOfDay)
                                .filter(nextDate.startOfDay > Column(ExerciseEntry.Columns.startTime.name))
                                .order(Column(ExerciseEntry.Columns.startTime.name))
                                .fetchAll(db)

                            promise(.success(result))
                        } else {
                            let result = try ExerciseEntry
                                .filter(sql: "\(ExerciseEntry.Columns.startTime.name) >= datetime('now', '-\(DirectConfig.lastChartHours) hours')")
                                .order(Column(ExerciseEntry.Columns.startTime.name))
                                .fetchAll(db)

                            promise(.success(result))
                        }
                    } catch {
                        promise(.failure(.withError(error)))
                    }
                }
            }
        }
    }
}
