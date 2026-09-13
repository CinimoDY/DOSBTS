//
//  LabSweepStore.swift
//  DOSBTSApp
//
//  Raw-row loader for `LAB: SWEEP` (DMNC-1503, Chart Lab P3). The persisted
//  `MealImpact` rows stop at 30 days and only exist for meals whose 2 h window has
//  closed, so a 90-day sweep set has to be recomputed from raw readings.
//
//  ONE `asyncRead`, following `ClinicReportStore.getClinicReportData` (:22-70):
//  fetch the whole period's rows once and slice them per meal in Swift. Never a
//  read per meal — N+1 on the serialized `DatabaseQueue` stalls the app. NO writes
//  inside the read (GRDB deadlock rule,
//  docs/solutions/logic-errors/grdb-write-inside-asyncread-deadlock-20260420.md).
//

import Combine
import Foundation
import GRDB

// MARK: - LabSweepRaw

/// Everything `SweepStatistics.build` needs, straight off disk.
struct LabSweepRaw {
    let days: Int
    let meals: [MealEntry]
    let readings: [SensorGlucose]
    let deliveries: [InsulinDelivery]
    let exercise: [ExerciseEntry]
    let now: Date
}

// MARK: - LabSweepStore

enum LabSweepStore {
    /// The sweep read is capped at 90 days.
    ///
    /// `ChartZoomRow`'s ALL chip dispatches `DaysZoom.allDays` (9999), which is a
    /// deliberate sentinel for the statistics SQL. Handing it to this read would
    /// pull every reading the user has ever recorded into memory to draw at most
    /// 120 sweeps. ALL therefore behaves as 90 d here, which is also the plan's
    /// contract.
    static let maxDays = 90

    static func effectiveDays(_ days: Int) -> Int {
        min(max(days, 1), maxDays)
    }
}

// MARK: - DataStore + LabSweepRaw

extension DataStore {
    /// Fetch the sweep period's meals, readings, deliveries and exercise in ONE read.
    ///
    /// The reading window starts 30 minutes *before* the meal cutoff so the oldest
    /// meal in the period still has its pre-meal baseline and its −30 min lead-in —
    /// a narrower fetch would silently return `noBaseline` for it (see
    /// docs/solutions/logic-errors/grdb-mismatched-fetch-windows-silent-zero-result-20260704.md).
    func getLabSweepRaw(days: Int) -> Future<LabSweepRaw, DirectError> {
        let effectiveDays = LabSweepStore.effectiveDays(days)

        return Future { promise in
            guard let dbQueue = self.dbQueue else {
                promise(.failure(.withMessage("LabSweepStore: no database")))
                return
            }

            dbQueue.asyncRead { asyncDB in
                do {
                    let db = try asyncDB.get()
                    let now = Date()
                    let cutoff = now.addingTimeInterval(-Double(effectiveDays) * 24 * 3600)
                    let readingCutoff = cutoff.addingTimeInterval(
                        Double(SweepStatistics.windowStartMinutes) * 60
                    )

                    let meals = try MealEntry
                        .filter(Column(MealEntry.Columns.timestamp.name) >= cutoff)
                        .order(Column(MealEntry.Columns.timestamp.name))
                        .fetchAll(db)

                    let readings = try SensorGlucose
                        .filter(Column(SensorGlucose.Columns.timestamp.name) >= readingCutoff)
                        .order(Column(SensorGlucose.Columns.timestamp.name))
                        .fetchAll(db)

                    // Type-filtered in Swift: `InsulinType` is Codable, not SQL-native.
                    let deliveries = try InsulinDelivery
                        .filter(Column(InsulinDelivery.Columns.starts.name) >= cutoff)
                        .order(Column(InsulinDelivery.Columns.starts.name))
                        .fetchAll(db)

                    // Filtered on `endTime`, NOT `startTime`: the overlap rule the
                    // builder applies is `endTime >= meal.timestamp`, so a session that
                    // began before the cutoff but ran into the oldest meal in the
                    // period still confounds it. A `startTime` filter would drop it
                    // and silently mark that meal clean.
                    let exercise = try ExerciseEntry
                        .filter(Column(ExerciseEntry.Columns.endTime.name) >= cutoff)
                        .order(Column(ExerciseEntry.Columns.startTime.name))
                        .fetchAll(db)

                    promise(.success(LabSweepRaw(
                        days: effectiveDays,
                        meals: meals,
                        readings: readings,
                        deliveries: deliveries,
                        exercise: exercise,
                        now: now
                    )))
                } catch {
                    promise(.failure(.withError(error)))
                }
            }
        }
    }
}
