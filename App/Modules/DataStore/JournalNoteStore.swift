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

            return journalNoteReload(state: state, timestamps: journalNoteValues.map(\.timestamp))

        case .deleteJournalNote(journalNote: let journalNote):
            DataStore.shared.deleteJournalNote(journalNote)

            return journalNoteReload(state: state, timestamps: [journalNote.timestamp])

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

// MARK: - Reload fan-out

/// Reload the Log tab's list and — when the note lands on the day the Digest
/// tab is currently showing — that screen's event timeline too. The add-note
/// button lives ON the Digest screen, so reloading only the Log tab's array
/// makes the button read as broken.
///
/// Deliberately NOT `.loadDailyDigest`: for today that skips the cache,
/// recomputes a `DailyDigest` with `aiInsight` unset, and `saveDailyDigest`
/// `insert(onConflict: .replace)`s straight over the stored insight — after
/// which `DailyDigestMiddleware` sees a nil insight plus consent plus a key and
/// fires a paid Claude call for every note added. Refreshing just the events
/// skips `computeDailyDigest`/`saveDailyDigest` entirely: no insight is lost
/// and no generation is triggered.
private func journalNoteReload(state: DirectState, timestamps: [Date]) -> AnyPublisher<DirectAction, DirectError> {
    let reloadList = Just(DirectAction.loadJournalNoteValues)
        .setFailureType(to: DirectError.self)
        .eraseToAnyPublisher()

    guard let digestDate = state.currentDailyDigest?.date,
          shouldRefreshDigestEvents(digestDate: digestDate, noteTimestamps: timestamps)
    else {
        return reloadList
    }

    let refreshDigestEvents = DataStore.shared.getDailyEvents(date: digestDate)
        .map { DirectAction.setDailyDigestEvents(events: $0) }
        .eraseToAnyPublisher()

    return Publishers.Merge(reloadList, refreshDigestEvents).eraseToAnyPublisher()
}

/// No digest on screen, or the note belongs to a different day: nothing on the
/// Digest tab is stale, so don't spend a read on it. Pure and internal so the
/// guard is testable without a database.
func shouldRefreshDigestEvents(digestDate: Date?, noteTimestamps: [Date]) -> Bool {
    guard let digestDate = digestDate else {
        return false
    }
    return noteTimestamps.contains { Calendar.current.isDate($0, inSameDayAs: digestDate) }
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
            // `guard … else { promise(.success([])); return }`, not `if let`:
            // an `if let` that falls through never fulfils the promise, so the
            // publisher hangs forever and every downstream `.loadJournalNoteValues`
            // is silently swallowed. This is `DailyDigestStore`'s form, and the
            // better one — `getMealEntryValues`, which this was cloned from,
            // still has the `if let` flaw (out of scope here).
            guard let dbQueue = self.dbQueue else {
                promise(.success([]))
                return
            }

            dbQueue.asyncRead { asyncDB in
                do {
                    let db = try asyncDB.get()

                    // `id` breaks the tie on both paths: JournalNote rounds its
                    // timestamp to the minute, so timestamp alone leaves
                    // same-minute notes in undefined order.
                    if let selectedDate = selectedDate, let nextDate = Calendar.current.date(byAdding: .day, value: +1, to: selectedDate) {
                        let result = try JournalNote
                            .filter(Column(JournalNote.Columns.timestamp.name) >= selectedDate.startOfDay)
                            .filter(nextDate.startOfDay > Column(JournalNote.Columns.timestamp.name))
                            .order(Column(JournalNote.Columns.timestamp.name), Column(JournalNote.Columns.id.name))
                            .fetchAll(db)

                        promise(.success(result))
                    } else {
                        let result = try JournalNote
                            .filter(sql: "\(JournalNote.Columns.timestamp.name) >= datetime('now', '-\(DirectConfig.lastChartHours) hours')")
                            .order(Column(JournalNote.Columns.timestamp.name), Column(JournalNote.Columns.id.name))
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
