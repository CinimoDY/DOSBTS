//
//  InsulinDeliveryStore.swift
//  DOSBTSApp
//

import Combine
import Foundation
import GRDB

func insulinDeliveryStoreMiddleware() -> Middleware<DirectState, DirectAction> {
    return { state, action, _ in
        switch action {
        case .startup:
            DataStore.shared.createInsulinDeliveryTable()

            return DataStore.shared.getFirstInsulinDeliveryDate().map { minSelectedDate in
                DirectAction.setMinSelectedDate(minSelectedDate: minSelectedDate)
            }.eraseToAnyPublisher()

        case .addInsulinDelivery(insulinDeliveryValues: let insulinDeliveryValues):
            guard !insulinDeliveryValues.isEmpty else {
                break
            }
            // Async write — emit .loadInsulinDeliveryValues from the completion.
            // The reducer already did an optimistic in-memory append so the
            // chart marker shows immediately; the reload is a defensive re-sync.
            return DataStore.shared.insertInsulinDelivery(insulinDeliveryValues)
                .map { _ in DirectAction.loadInsulinDeliveryValues }
                .eraseToAnyPublisher()

        case .restoreInsulinDelivery(insulinDelivery: let insulinDelivery):
            return DataStore.shared.insertInsulinDelivery([insulinDelivery])
                .map { _ in DirectAction.loadInsulinDeliveryValues }
                .eraseToAnyPublisher()

        case .deleteInsulinDelivery(insulinDelivery: let insulinDelivery):
            return DataStore.shared.deleteInsulinDelivery(insulinDelivery)
                .map { _ in DirectAction.loadInsulinDeliveryValues }
                .eraseToAnyPublisher()

        case .updateInsulinDelivery(insulinDelivery: let insulinDelivery):
            return DataStore.shared.updateInsulinDelivery(insulinDelivery)
                .map { _ in DirectAction.loadInsulinDeliveryValues }
                .eraseToAnyPublisher()

        case .setSelectedDate(selectedDate: _):
            return Just(DirectAction.loadInsulinDeliveryValues)
                .setFailureType(to: DirectError.self)
                .eraseToAnyPublisher()

        case .loadInsulinDeliveryValues:
            guard state.appState == .active else {
                break
            }

            return DataStore.shared.getInsulinDeliveryValues(selectedDate: state.selectedDate).map { insulinDeliveryValues in
                DirectAction.setInsulinDeliveryValues(insulinDeliveryValues: insulinDeliveryValues)
            }.eraseToAnyPublisher()

        case .setAppState(appState: let appState):
            guard appState == .active else {
                break
            }

            return Just(DirectAction.loadInsulinDeliveryValues)
                .setFailureType(to: DirectError.self)
                .eraseToAnyPublisher()

        default:
            break
        }

        return Empty().eraseToAnyPublisher()
    }
}

// `internal` (not `private`) so the App Intents in App/Intents/ can call
// insertInsulinDelivery directly when Siri invokes them outside the
// Redux dispatch path (DMNC-633).
extension DataStore {
    func createInsulinDeliveryTable() {
        if let dbQueue = dbQueue {
            do {
                try dbQueue.write { db in
                    try db.create(table: InsulinDelivery.Table, ifNotExists: true) { t in
                        t.column(InsulinDelivery.Columns.id.name, .text)
                            .primaryKey()
                        t.column(InsulinDelivery.Columns.starts.name, .date)
                            .notNull()
                            .indexed()
                        t.column(InsulinDelivery.Columns.ends.name, .date)
                            .notNull()
                            .indexed()
                        t.column(InsulinDelivery.Columns.units.name, .double)
                            .notNull()
                        t.column(InsulinDelivery.Columns.type.name, .text)
                            .notNull()
                            .indexed()
                        t.column(InsulinDelivery.Columns.timegroup.name, .date)
                            .notNull()
                            .indexed()
                    }
                }
            } catch {
                DirectLog.error("\(error)")
            }
        }
    }

    func deleteAllInsulinDelivery() {
        if let dbQueue = dbQueue {
            do {
                try dbQueue.write { db in
                    do {
                        try InsulinDelivery.deleteAll(db)
                    } catch {
                        DirectLog.error("\(error)")
                    }
                }
            } catch {
                DirectLog.error("\(error)")
            }
        }
    }

    /// Async-write variants — DMNC-905. The previous sync `dbQueue.write` calls
    /// blocked the dispatch thread (main) for the full duration of the GRDB
    /// write, which stalled SwiftUI's runloop and made the reducer's optimistic
    /// state update invisible to `.onChange` observers until the write returned.
    /// Returning a Future lets the middleware emit `.loadInsulinDeliveryValues`
    /// from the completion handler without blocking the dispatch thread.
    func deleteInsulinDelivery(_ value: InsulinDelivery) -> Future<Void, DirectError> {
        return Future { promise in
            guard let dbQueue = self.dbQueue else {
                promise(.success(()))
                return
            }
            dbQueue.asyncWrite({ db in
                try InsulinDelivery.deleteOne(db, id: value.id)
            }, completion: { _, result in
                switch result {
                case .success: promise(.success(()))
                case .failure(let error):
                    DirectLog.error("\(error)")
                    promise(.failure(.withError(error)))
                }
            })
        }
    }

    func updateInsulinDelivery(_ value: InsulinDelivery) -> Future<Void, DirectError> {
        return Future { promise in
            guard let dbQueue = self.dbQueue else {
                promise(.success(()))
                return
            }
            dbQueue.asyncWrite({ db in
                try value.update(db)
            }, completion: { _, result in
                switch result {
                case .success: promise(.success(()))
                case .failure(let error):
                    DirectLog.error("\(error)")
                    promise(.failure(.withError(error)))
                }
            })
        }
    }

    func insertInsulinDelivery(_ values: [InsulinDelivery]) -> Future<Void, DirectError> {
        return Future { promise in
            guard let dbQueue = self.dbQueue else {
                promise(.success(()))
                return
            }
            dbQueue.asyncWrite({ db in
                for value in values {
                    try value.insert(db)
                }
            }, completion: { _, result in
                switch result {
                case .success: promise(.success(()))
                case .failure(let error):
                    DirectLog.error("\(error)")
                    promise(.failure(.withError(error)))
                }
            })
        }
    }

    func getFirstInsulinDeliveryDate() -> Future<Date, DirectError> {
        return Future { promise in
            if let dbQueue = self.dbQueue {
                dbQueue.asyncRead { asyncDB in
                    do {
                        let db = try asyncDB.get()

                        if let date = try Date.fetchOne(db, sql: "SELECT MIN(starts) FROM \(InsulinDelivery.Table)") {
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

    func getInsulinDeliveryValues(selectedDate: Date? = nil) -> Future<[InsulinDelivery], DirectError> {
        return Future { promise in
            if let dbQueue = self.dbQueue {
                dbQueue.asyncRead { asyncDB in
                    do {
                        let db = try asyncDB.get()

                        if let selectedDate = selectedDate, let nextDate = Calendar.current.date(byAdding: .day, value: +1, to: selectedDate) {
                            let result = try InsulinDelivery
                                .filter(Column(InsulinDelivery.Columns.starts.name) >= selectedDate.startOfDay)
                                .filter(nextDate.startOfDay > Column(InsulinDelivery.Columns.starts.name))
                                .order(Column(InsulinDelivery.Columns.starts.name))
                                .fetchAll(db)

                            promise(.success(result))
                        } else {
                            let result = try InsulinDelivery
                                .filter(sql: "\(InsulinDelivery.Columns.starts.name) >= datetime('now', '-\(DirectConfig.lastChartHours) hours') OR \(InsulinDelivery.Columns.ends.name) >= datetime('now', '-\(DirectConfig.lastChartHours) hours')")
                                .order(Column(InsulinDelivery.Columns.starts.name))
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

extension DataStore {
    func getIOBDeliveries(diaMinutes: Int) -> Future<[InsulinDelivery], DirectError> {
        return Future { promise in
            guard let dbQueue = self.dbQueue else {
                promise(.success([]))
                return
            }

            dbQueue.asyncRead { asyncDB in
                do {
                    let db = try asyncDB.get()
                    let result = try InsulinDelivery
                        .filter(sql: "\(InsulinDelivery.Columns.starts.name) >= datetime('now', '-\(diaMinutes) minutes') OR \(InsulinDelivery.Columns.ends.name) >= datetime('now', '-\(diaMinutes) minutes')")
                        .order(Column(InsulinDelivery.Columns.starts.name))
                        .fetchAll(db)
                    promise(.success(result))
                } catch {
                    promise(.failure(.withError(error)))
                }
            }
        }
    }
}
