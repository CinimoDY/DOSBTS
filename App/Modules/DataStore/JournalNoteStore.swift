//
//  JournalNoteStore.swift
//  DOSBTSApp
//
//  https://github.com/groue/GRDB.swift
//

import Combine
import Foundation
import GRDB

func journalNoteStoreMiddleware() -> Middleware<DirectState, DirectAction> {
    return { state, action, _ in
        switch action {
        case .startup:
            DataStore.shared.createJournalNoteTable()

        case .addJournalNote(journalNoteValues: let journalNoteValues):
            guard !journalNoteValues.isEmpty else {
                break
            }

            DataStore.shared.insertJournalNote(journalNoteValues)

            return Just(DirectAction.loadJournalNoteValues)
                .setFailureType(to: DirectError.self)
                .eraseToAnyPublisher()

        case .deleteJournalNote(journalNote: let journalNote):
            DataStore.shared.deleteJournalNote(journalNote)

            return Just(DirectAction.loadJournalNoteValues)
                .setFailureType(to: DirectError.self)
                .eraseToAnyPublisher()

        case .setSelectedDate(selectedDate: _):
            return Just(DirectAction.loadJournalNoteValues)
                .setFailureType(to: DirectError.self)
                .eraseToAnyPublisher()

        case .loadJournalNoteValues:
            // Every DataStore middleware guards `.active` — a load dispatched
            // while the app is inactive races the ContentView.onAppear that
            // sets it (docs/solutions/logic-errors/appstate-inactive-blocks-data-loading-20260317.md).
            guard state.appState == .active else {
                break
            }

            return DataStore.shared.getJournalNoteValues(selectedDate: state.selectedDate).map { journalNoteValues in
                DirectAction.setJournalNoteValues(journalNoteValues: journalNoteValues)
            }.eraseToAnyPublisher()

        case .setAppState(appState: let appState):
            guard appState == .active else {
                break
            }

            return Just(DirectAction.loadJournalNoteValues)
                .setFailureType(to: DirectError.self)
                .eraseToAnyPublisher()

        default:
            break
        }

        return Empty().eraseToAnyPublisher()
    }
}

private extension DataStore {
    func createJournalNoteTable() {
        if let dbQueue = dbQueue {
            do {
                try dbQueue.write { db in
                    try db.create(table: JournalNote.Table, ifNotExists: true) { t in
                        t.column(JournalNote.Columns.id.name, .text)
                            .primaryKey()
                        t.column(JournalNote.Columns.timestamp.name, .date)
                            .notNull()
                            .indexed()
                        t.column(JournalNote.Columns.text.name, .text)
                            .notNull()
                        // Nullable: a note without a tag is the default.
                        t.column(JournalNote.Columns.tag.name, .text)
                    }
                }
            } catch {
                DirectLog.error("\(error)")
            }
        }
    }

    func deleteJournalNote(_ value: JournalNote) {
        if let dbQueue = dbQueue {
            do {
                try dbQueue.write { db in
                    do {
                        try JournalNote.deleteOne(db, id: value.id)
                    } catch {
                        DirectLog.error("\(error)")
                    }
                }
            } catch {
                DirectLog.error("\(error)")
            }
        }
    }

    func insertJournalNote(_ values: [JournalNote]) {
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

    /// Read-only: never write from inside `asyncRead` — the DatabaseQueue
    /// serializes access and a nested write deadlocks
    /// (docs/solutions/logic-errors/grdb-write-inside-asyncread-deadlock-20260420.md).
    func getJournalNoteValues(selectedDate: Date? = nil) -> Future<[JournalNote], DirectError> {
        return Future { promise in
            if let dbQueue = self.dbQueue {
                dbQueue.asyncRead { asyncDB in
                    do {
                        let db = try asyncDB.get()

                        if let selectedDate = selectedDate, let nextDate = Calendar.current.date(byAdding: .day, value: +1, to: selectedDate) {
                            let result = try JournalNote
                                .filter(Column(JournalNote.Columns.timestamp.name) >= selectedDate.startOfDay)
                                .filter(nextDate.startOfDay > Column(JournalNote.Columns.timestamp.name))
                                .order(Column(JournalNote.Columns.timestamp.name))
                                .fetchAll(db)

                            promise(.success(result))
                        } else {
                            let result = try JournalNote
                                .filter(sql: "\(JournalNote.Columns.timestamp.name) >= datetime('now', '-\(DirectConfig.lastChartHours) hours')")
                                .order(Column(JournalNote.Columns.timestamp.name))
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
