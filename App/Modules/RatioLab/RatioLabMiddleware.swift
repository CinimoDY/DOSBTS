//
//  RatioLabMiddleware.swift
//  DOSBTSApp
//
//  On-demand evidence loader for the Ratio Lab (DMNC-1298, WP-R2).
//  Dispatching `.loadRatioEvidence` fetches all evidence for ICR/ISF estimation
//  in ONE asyncRead — no writes inside (GRDB deadlock rule).
//
//  Data flow:
//    RatioLabView.onAppear → .loadRatioEvidence
//      ratioLabMiddleware (guard .active)
//        └─ DataStore.getRatioEvidence()
//             → .setRatioEvidence(evidence:)
//    RatioLabView renders RatioEstimator.estimate(evidence) (pure)
//

import Combine
import Foundation
import GRDB

func ratioLabMiddleware() -> Middleware<DirectState, DirectAction> {
    return { state, action, _ in
        switch action {
        case .loadRatioEvidence:
            guard state.appState == .active else {
                break
            }

            return DataStore.shared.getRatioEvidence().map { evidence in
                DirectAction.setRatioEvidence(evidence: evidence)
            }.eraseToAnyPublisher()

        default:
            break
        }

        return Empty().eraseToAnyPublisher()
    }
}

// MARK: - DataStore + RatioEvidence

extension DataStore {
    /// Fetches all evidence needed by `RatioEstimator` in ONE asyncRead.
    ///
    /// - 14-day InsulinDelivery window for TDD + bolus pairing (type-filtered in Swift
    ///   because `InsulinType` is Codable, not SQL-filterable).
    /// - 30-day clean MealImpact window joined in Swift to MealEntry.
    /// - Per-candidate SensorGlucose window [t, t+135 min] for endGlucose + minInWindow.
    /// - Paired meal/snack boluses within ±15 min (from the 14-day delivery set).
    ///
    /// NO writes inside this method — GRDB deadlock rule applies.
    func getRatioEvidence() -> Future<RatioEvidence, DirectError> {
        return Future { promise in
            guard let dbQueue = self.dbQueue else {
                promise(.success(RatioEvidence(tddDays: [], mealObservations: [])))
                return
            }

            dbQueue.asyncRead { asyncDB in
                do {
                    let db = try asyncDB.get()
                    let now = Date()
                    let calendar = Calendar.current
                    let startOfToday = calendar.startOfDay(for: now)

                    guard let tddWindowStart = calendar.date(
                        byAdding: .day,
                        value: -RatioEstimator.tddLookbackDays,
                        to: startOfToday
                    ) else {
                        promise(.success(RatioEvidence(tddDays: [], mealObservations: [])))
                        return
                    }

                    // 1. InsulinDelivery — 14-day window; type-filter deferred to Swift because
                    //    InsulinType is Codable (not a SQL-native type).
                    let allDeliveries = try InsulinDelivery
                        .filter(Column(InsulinDelivery.Columns.starts.name) >= tddWindowStart)
                        .filter(Column(InsulinDelivery.Columns.starts.name) < startOfToday)
                        .order(Column(InsulinDelivery.Columns.starts.name))
                        .fetchAll(db)

                    let tddDays = RatioEstimator.tddDays(from: allDeliveries, asOf: now, calendar: calendar)

                    // 2. Clean MealImpacts — 30-day backfill bound (matches MealImpactStore).
                    let mealImpactCutoff = now.addingTimeInterval(-30 * 24 * 3600)
                    let cleanImpacts = try MealImpact
                        .filter(Column(MealImpact.Columns.isClean.name) == true)
                        .filter(Column(MealImpact.Columns.timestamp.name) >= mealImpactCutoff)
                        .fetchAll(db)

                    guard !cleanImpacts.isEmpty else {
                        promise(.success(RatioEvidence(tddDays: tddDays, mealObservations: [])))
                        return
                    }

                    // 3. Join to MealEntry in Swift by mealEntryId.
                    let idStrings = cleanImpacts.map { $0.mealEntryId.uuidString.uppercased() }
                    let mealEntries = try MealEntry
                        .filter(idStrings.contains(Column(MealEntry.Columns.id.name)))
                        .fetchAll(db)
                    let mealById = Dictionary(uniqueKeysWithValues: mealEntries.map { ($0.id, $0) })

                    // 4. Per candidate: SensorGlucose window + bolus pairing.
                    let upperWindowSeconds = TimeInterval(RatioEstimator.endGlucoseWindowUpperMinutes * 60)
                    let mealObservations: [MealObservation] = try cleanImpacts.compactMap { impact in
                        guard let meal = mealById[impact.mealEntryId] else { return nil }

                        let t = meal.timestamp
                        let windowEnd = t.addingTimeInterval(upperWindowSeconds)

                        let readings = try SensorGlucose
                            .filter(Column(SensorGlucose.Columns.timestamp.name) >= t)
                            .filter(Column(SensorGlucose.Columns.timestamp.name) <= windowEnd)
                            .order(Column(SensorGlucose.Columns.timestamp.name))
                            .fetchAll(db)

                        let endGlucose = RatioEstimator.endGlucose(mealTimestamp: t, readings: readings)
                        let minInWindow = RatioEstimator.minGlucoseInWindow(mealTimestamp: t, readings: readings)
                        let pairedBolus = RatioEstimator.pairedBolusUnits(
                            mealTimestamp: t,
                            deliveries: allDeliveries
                        )

                        return MealObservation(
                            meal: meal,
                            impact: impact,
                            pairedBolusUnits: pairedBolus,
                            endGlucose: endGlucose,
                            minGlucoseInWindow: minInWindow
                        )
                    }

                    promise(.success(RatioEvidence(tddDays: tddDays, mealObservations: mealObservations)))
                } catch {
                    promise(.failure(.withError(error)))
                }
            }
        }
    }
}
