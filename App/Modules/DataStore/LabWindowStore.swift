//
//  LabWindowStore.swift
//  DOSBTSApp
//
//  Chart Lab P1 (DMNC-1506) — the GRDB half of the whole-system window loader.
//
//  ONE `asyncRead` for the whole interval, never per-stream or per-day in a loop
//  (N+1 reads on the serialized DatabaseQueue stall the app), and NO writes
//  inside it (grdb-write-inside-asyncread-deadlock-20260420). The shape is
//  `ClinicReportStore.getClinicReportData(days:)`'s, line for line.
//

import Combine
import Foundation
import GRDB

extension DataStore {
    /// Every GRDB stream for one interval, in one read.
    ///
    /// - Parameters:
    ///   - interval: the window a lab tab is drawing.
    ///   - leadHours: how far BEFORE the window to reach for event rows, so a
    ///     meal ribbon or an exercise span that began before the window's left
    ///     edge still draws (the night window's whole point — dinner happens
    ///     before 20:00 sometimes, and its response runs into the night).
    ///   - iobLookbackMinutes: `max(bolusDIA, basalDIA)` — an evening bolus's
    ///     IOB tail has to be able to decay across midnight.
    func getLabWindowRaw(
        interval: DateInterval,
        leadHours: Double = 4,
        iobLookbackMinutes: Int
    ) -> Future<LabWindowRaw, DirectError> {
        return Future { promise in
            guard let dbQueue = self.dbQueue else {
                promise(.failure(.withMessage("LabWindowStore: no database")))
                return
            }

            dbQueue.asyncRead { asyncDB in
                do {
                    let db = try asyncDB.get()

                    let windowStart = interval.start
                    let windowEnd = interval.end
                    let lead = windowStart.addingTimeInterval(-leadHours * 3600)
                    let iobStart = windowStart.addingTimeInterval(-Double(iobLookbackMinutes) * 60)

                    // Readings get the lead too: a meal logged at 19:05 needs
                    // its PRE-meal baseline to compute an honest response delta,
                    // and that reading is before the window. Charts clips the
                    // extra to the domain, and `readingsInWindow` is what every
                    // coverage number counts, so the lead cannot inflate `GLU %`.
                    let readings = try SensorGlucose
                        .filter(Column(SensorGlucose.Columns.timestamp.name) >= lead)
                        .filter(Column(SensorGlucose.Columns.timestamp.name) <= windowEnd)
                        .order(Column(SensorGlucose.Columns.timestamp.name))
                        .fetchAll(db)

                    let bloodGlucose = try BloodGlucose
                        .filter(Column(BloodGlucose.Columns.timestamp.name) >= lead)
                        .filter(Column(BloodGlucose.Columns.timestamp.name) <= windowEnd)
                        .order(Column(BloodGlucose.Columns.timestamp.name))
                        .fetchAll(db)

                    let meals = try MealEntry
                        .filter(Column(MealEntry.Columns.timestamp.name) >= lead)
                        .filter(Column(MealEntry.Columns.timestamp.name) <= windowEnd)
                        .order(Column(MealEntry.Columns.timestamp.name))
                        .fetchAll(db)

                    let deliveries = try InsulinDelivery
                        .filter(Column(InsulinDelivery.Columns.starts.name) >= lead)
                        .filter(Column(InsulinDelivery.Columns.starts.name) <= windowEnd)
                        .order(Column(InsulinDelivery.Columns.starts.name))
                        .fetchAll(db)

                    // A DIA-wide superset of `deliveries`: the IOB area needs
                    // every dose still decaying at the window's left edge.
                    let iobDeliveries = try InsulinDelivery
                        .filter(Column(InsulinDelivery.Columns.starts.name) >= iobStart)
                        .filter(Column(InsulinDelivery.Columns.starts.name) <= windowEnd)
                        .order(Column(InsulinDelivery.Columns.starts.name))
                        .fetchAll(db)

                    // Ends, not starts: a run that finished inside the window
                    // belongs to it even if it began before the lead.
                    let exercise = try ExerciseEntry
                        .filter(Column(ExerciseEntry.Columns.endTime.name) >= lead)
                        .filter(Column(ExerciseEntry.Columns.startTime.name) <= windowEnd)
                        .order(Column(ExerciseEntry.Columns.startTime.name))
                        .fetchAll(db)

                    let notes = try JournalNote
                        .filter(Column(JournalNote.Columns.timestamp.name) >= lead)
                        .filter(Column(JournalNote.Columns.timestamp.name) <= windowEnd)
                        .order(Column(JournalNote.Columns.timestamp.name))
                        .fetchAll(db)

                    promise(.success(LabWindowRaw(
                        readings: readings,
                        bloodGlucose: bloodGlucose,
                        meals: meals,
                        deliveries: deliveries,
                        iobDeliveries: iobDeliveries,
                        exercise: exercise,
                        notes: notes
                    )))
                } catch {
                    promise(.failure(.withError(error)))
                }
            }
        }
    }
}
