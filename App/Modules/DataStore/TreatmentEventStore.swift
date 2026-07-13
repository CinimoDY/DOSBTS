//
//  TreatmentEventStore.swift
//  DOSBTSApp
//

import Combine
import Foundation
import GRDB

func treatmentEventStoreMiddleware() -> Middleware<DirectState, DirectAction> {
    return { state, action, _ in
        switch action {
        case .startup:
            DataStore.shared.createTreatmentEventTable()

            return Empty().eraseToAnyPublisher()

        case .addTreatmentEvent(treatmentEvent: let treatmentEvent):
            guard state.appState == .active else {
                return Empty().eraseToAnyPublisher()
            }

            DataStore.shared.insertTreatmentEvent(treatmentEvent)

            return Empty().eraseToAnyPublisher()

        default:
            break
        }

        return Empty().eraseToAnyPublisher()
    }
}

private extension DataStore {
    func createTreatmentEventTable() {
        if let dbQueue = dbQueue {
            do {
                try dbQueue.write { db in
                    try db.create(table: TreatmentEvent.Table, ifNotExists: true) { t in
                        t.column(TreatmentEvent.Columns.id.name, .text)
                            .primaryKey()
                        t.column(TreatmentEvent.Columns.mealEntryId.name, .text)
                            .notNull()
                            .indexed()
                        t.column(TreatmentEvent.Columns.alarmFiredAt.name, .date)
                            .notNull()
                        t.column(TreatmentEvent.Columns.treatmentLoggedAt.name, .date)
                            .notNull()
                            .indexed()
                        t.column(TreatmentEvent.Columns.treatmentType.name, .text)
                            .notNull()
                        t.column(TreatmentEvent.Columns.glucoseAtTreatment.name, .integer)
                            .notNull()
                        t.column(TreatmentEvent.Columns.countdownMinutes.name, .integer)
                            .notNull()
                        t.column(TreatmentEvent.Columns.timegroup.name, .date)
                            .notNull()
                            .indexed()
                    }
                }
            } catch {
                DirectLog.error("TreatmentEventStore.createTreatmentEventTable: \(error)")
            }
        }
    }

    func insertTreatmentEvent(_ value: TreatmentEvent) {
        if let dbQueue = dbQueue {
            do {
                try dbQueue.write { db in
                    do {
                        try value.insert(db)
                    } catch {
                        DirectLog.error("TreatmentEventStore.insertTreatmentEvent: write error: \(error)")
                    }
                }
            } catch {
                DirectLog.error("TreatmentEventStore.insertTreatmentEvent: transaction error: \(error)")
            }
        }
    }
}
