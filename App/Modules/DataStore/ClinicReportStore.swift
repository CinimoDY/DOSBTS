//
//  ClinicReportStore.swift
//  DOSBTSApp
//
//  On-demand raw-data loader for the clinic report (DMNC-1304). Fetches the period's
//  readings + events in ONE asyncRead — no writes inside (GRDB deadlock rule). The
//  middleware zips this with `getSensorGlucoseStatistics` and assembles via
//  `ClinicReportBuilder`.
//

import Combine
import Foundation
import GRDB

extension DataStore {
    /// Fetch everything the clinic report needs (except SQL statistics, fetched separately)
    /// for the last `days` days in ONE read: readings (hourly pattern + hypo episodes),
    /// deliveries (bolus-by-type + basal counts), and the meal count.
    ///
    /// Fetched once, ordered, in a single asyncRead — never per-hour/per-day in a loop
    /// (N+1 reads on the serialized DatabaseQueue stall the app). NO writes.
    func getClinicReportData(days: Int) -> Future<ClinicReportRaw, DirectError> {
        return Future { promise in
            guard let dbQueue = self.dbQueue else {
                promise(.failure(.withMessage("ClinicReportStore: no database")))
                return
            }

            dbQueue.asyncRead { asyncDB in
                do {
                    let db = try asyncDB.get()
                    let now = Date()
                    let cutoff = now.addingTimeInterval(-Double(days) * 24 * 3600)

                    let readings = try SensorGlucose
                        .filter(Column(SensorGlucose.Columns.timestamp.name) >= cutoff)
                        .order(Column(SensorGlucose.Columns.timestamp.name))
                        .fetchAll(db)

                    // Type counts happen in Swift — InsulinType is Codable, not SQL-filterable.
                    let deliveries = try InsulinDelivery
                        .filter(Column(InsulinDelivery.Columns.starts.name) >= cutoff)
                        .fetchAll(db)

                    let mealCount = try MealEntry
                        .filter(Column(MealEntry.Columns.timestamp.name) >= cutoff)
                        .fetchCount(db)

                    promise(.success(ClinicReportRaw(
                        readings: readings,
                        deliveries: deliveries,
                        mealCount: mealCount,
                        period: DateInterval(start: cutoff, end: now)
                    )))
                } catch {
                    promise(.failure(.withError(error)))
                }
            }
        }
    }
}
