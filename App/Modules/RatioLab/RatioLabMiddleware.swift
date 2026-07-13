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
            // Silently drops when not .active, with NO .setAppState(.active) re-trigger:
            // this load is on-demand from RatioLabView.onAppear, which can only run
            // after ContentView sets .active. A future startup-path dispatch would
            // no-op here — add the re-trigger pattern if that ever becomes a thing.
            guard state.appState == .active else {
                break
            }

            // On a GRDB read error `getRatioEvidence()` emits `.failure`, which the
            // Store logs but never re-dispatches — so `.setRatioEvidence` would never
            // land and RatioLabView (which treats `ratioEvidence == nil` as loading)
            // would spin forever. Fall back to empty evidence: the screen shows its
            // safe empty / "collecting evidence" state instead of an endless spinner.
            return DataStore.shared.getRatioEvidence()
                .map { DirectAction.setRatioEvidence(evidence: $0) }
                .catch { error -> Just<DirectAction> in
                    DirectLog.error("Ratio Lab evidence load failed: \(error)")
                    return Just(.setRatioEvidence(evidence: RatioEvidence(tddDays: [], mealObservations: [])))
                }
                .setFailureType(to: DirectError.self)
                .eraseToAnyPublisher()

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
    /// - 30-day InsulinDelivery window for TDD + bolus pairing (type-filtered in Swift
    ///   because `InsulinType` is Codable, not SQL-filterable). The window matches the
    ///   meal-impact cutoff so bolus pairing works for confounded meals from days 15–30;
    ///   `RatioEstimator.tddDays` re-filters to the last 14 complete days internally.
    /// - 30-day clean MealImpact window joined in Swift to MealEntry.
    /// - Up to `RatioEstimator.maxConfoundedEvidenceRows` of the most-recent non-clean
    ///   MealImpacts from the same window. The estimator enforces `isClean == false →
    ///   .confounded` exclusion at criterion 1; these appear in the evidence table as
    ///   "CONFOUNDED" teaching rows. SensorGlucose reads are skipped for confounded
    ///   impacts since the estimator discards them before inspecting glucose values.
    /// - Per-clean-candidate SensorGlucose window [t, t+135 min] for endGlucose + minInWindow.
    /// - Paired meal/snack boluses within ±15 min (from the 30-day delivery set).
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

                    // Guard calendar arithmetic before touching the DB.
                    guard calendar.date(
                        byAdding: .day,
                        value: -RatioEstimator.tddLookbackDays,
                        to: startOfToday
                    ) != nil else {
                        promise(.success(RatioEvidence(tddDays: [], mealObservations: [])))
                        return
                    }

                    // Use the wider 30-day meal-impact window for the delivery fetch.
                    // This ensures `pairedBolusUnits` can pair boluses for confounded meals
                    // from days 15–30 (the previous 14-day window silently dropped them).
                    // `tddDays()` re-filters to the last 14 complete days internally, so
                    // TDD is unaffected. Today's deliveries are included — excluding them
                    // would mislabel a meal logged today as `.noBolus`.
                    // Type-filter is deferred to Swift because InsulinType is Codable (not SQL-native).
                    let mealImpactCutoff = now.addingTimeInterval(-30 * 24 * 3600)
                    let allDeliveries = try InsulinDelivery
                        .filter(Column(InsulinDelivery.Columns.starts.name) >= mealImpactCutoff)
                        .order(Column(InsulinDelivery.Columns.starts.name))
                        .fetchAll(db)

                    let tddDays = RatioEstimator.tddDays(from: allDeliveries, asOf: now, calendar: calendar)

                    // --- Correction candidates for empirical ISF (DMNC-1303) ---
                    // Independent of meal impacts (computed before the empty-impacts early
                    // return so a user with corrections but no scored meals still gets them).
                    // Most-recent corrections only; `allDeliveries` is time-ascending so
                    // `suffix` keeps the newest N.
                    let correctionCandidates = allDeliveries
                        .filter { $0.type == .correctionBolus }
                        .suffix(RatioEstimator.maxCorrectionCandidates)

                    let correctionImpacts: [InsulinImpact]
                    if correctionCandidates.isEmpty {
                        correctionImpacts = []
                    } else {
                        // Context fetched ONCE over the SAME 30-day window as the deliveries —
                        // a narrower fetch silently returns zero matches downstream (see
                        // docs/solutions/logic-errors/grdb-mismatched-fetch-windows-silent-zero-result-20260704.md).
                        let exercises = try ExerciseEntry
                            .filter(Column(ExerciseEntry.Columns.startTime.name) >= mealImpactCutoff)
                            .fetchAll(db)
                        let windowMeals = try MealEntry
                            .filter(Column(MealEntry.Columns.timestamp.name) >= mealImpactCutoff)
                            .fetchAll(db)

                        let toleranceSeconds = TimeInterval(RatioEstimator.correctionBaselineToleranceMinutes * 60)
                        let effectSeconds = TimeInterval(RatioEstimator.correctionEffectWindowMinutes * 60)
                        let nadirStartSeconds = TimeInterval(RatioEstimator.correctionNadirStartMinutes * 60)
                        let mealLookbackSeconds = TimeInterval(RatioEstimator.correctionMealLookbackMinutes * 60)
                        let stackLookbackSeconds = TimeInterval(RatioEstimator.correctionStackLookbackMinutes * 60)

                        correctionImpacts = try correctionCandidates.map { dose -> InsulinImpact in
                            let t = dose.starts
                            let windowStart = t.addingTimeInterval(-toleranceSeconds)
                            let windowEnd = t.addingTimeInterval(effectSeconds)

                            let readings = try SensorGlucose
                                .filter(Column(SensorGlucose.Columns.timestamp.name) >= windowStart)
                                .filter(Column(SensorGlucose.Columns.timestamp.name) <= windowEnd)
                                .order(Column(SensorGlucose.Columns.timestamp.name))
                                .fetchAll(db)

                            // Baseline: CGM reading nearest the dose within ±tolerance.
                            let baseline = readings
                                .filter { abs($0.timestamp.timeIntervalSince(t)) <= toleranceSeconds }
                                .min { abs($0.timestamp.timeIntervalSince(t)) < abs($1.timestamp.timeIntervalSince(t)) }?
                                .glucoseValue

                            // Nadir + coverage over the effect window [t+nadirStart, t+effect].
                            // Below the reading gate the nadir is left nil → scored as .noCGM.
                            let nadirWindowStart = t.addingTimeInterval(nadirStartSeconds)
                            let effectReadings = readings.filter { $0.timestamp >= nadirWindowStart && $0.timestamp <= windowEnd }
                            let hasCoverage = effectReadings.count >= RatioEstimator.correctionMinReadings
                            let nadirReading = hasCoverage ? effectReadings.min { $0.glucoseValue < $1.glucoseValue } : nil
                            let peakOffset = nadirReading.map { Int($0.timestamp.timeIntervalSince(t) / 60) }

                            // Confounders — external context only; RatioEstimator.scoreCorrection judges.
                            var confounders: [InsulinConfounder] = []
                            if let baseline, baseline < RatioEstimator.correctionMinStartMgDL {
                                confounders.append(.correctionForLow)
                            }
                            let mealWindowStart = t.addingTimeInterval(-mealLookbackSeconds)
                            if windowMeals.contains(where: {
                                ($0.carbsGrams ?? 0) >= RatioEstimator.minCarbsGrams
                                    && $0.timestamp >= mealWindowStart && $0.timestamp <= windowEnd
                            }) {
                                confounders.append(.mealInWindow)
                            }
                            let stackWindowStart = t.addingTimeInterval(-stackLookbackSeconds)
                            let stackedUnits = allDeliveries
                                .filter {
                                    $0.id != dose.id && $0.type != .basal
                                        && $0.starts >= stackWindowStart && $0.starts <= windowEnd
                                }
                                .reduce(0.0) { $0 + $1.units }
                            if stackedUnits > 0 { confounders.append(.stackedBolus(units: stackedUnits)) }
                            if exercises.contains(where: { $0.startTime <= windowEnd && $0.endTime >= t }) {
                                confounders.append(.exerciseInWindow)
                            }

                            // iobAtDose stays nil: retrospective at-date IOB is new machinery;
                            // stacking is detected by bolus proximity above instead.
                            return InsulinImpact.compute(
                                for: dose,
                                glucoseAtDose: baseline,
                                glucoseAtPeak: nadirReading?.glucoseValue,
                                peakOffsetMinutes: peakOffset,
                                iobAtDose: nil,
                                confounders: confounders
                            )
                        }
                    }

                    // 2a. Clean MealImpacts — 30-day backfill bound (matches MealImpactStore).
                    let cleanImpacts = try MealImpact
                        .filter(Column(MealImpact.Columns.isClean.name) == true)
                        .filter(Column(MealImpact.Columns.timestamp.name) >= mealImpactCutoff)
                        .fetchAll(db)

                    // 2b. Confounded MealImpacts — same window, capped so they don't crowd
                    //     out clean teaching rows. Most-recent N only.
                    let confoundedImpacts = try MealImpact
                        .filter(Column(MealImpact.Columns.isClean.name) == false)
                        .filter(Column(MealImpact.Columns.timestamp.name) >= mealImpactCutoff)
                        .order(Column(MealImpact.Columns.timestamp.name).desc)
                        .limit(RatioEstimator.maxConfoundedEvidenceRows)
                        .fetchAll(db)

                    let allImpacts = cleanImpacts + confoundedImpacts
                    guard !allImpacts.isEmpty else {
                        promise(.success(RatioEvidence(tddDays: tddDays, mealObservations: [], correctionImpacts: correctionImpacts)))
                        return
                    }

                    // 3. Join all impacts to MealEntry in Swift by mealEntryId.
                    let idStrings = allImpacts.map { $0.mealEntryId.uuidString.uppercased() }
                    let mealEntries = try MealEntry
                        .filter(idStrings.contains(Column(MealEntry.Columns.id.name)))
                        .fetchAll(db)
                    let mealById = Dictionary(uniqueKeysWithValues: mealEntries.map { ($0.id, $0) })

                    // 4. Per candidate: SensorGlucose window (clean only) + bolus pairing.
                    //    Confounded impacts skip the glucose reads — the estimator rejects them
                    //    at criterion 1 (`!isClean → .confounded`) before inspecting endGlucose
                    //    or minGlucoseInWindow, so the DB reads would be dead work.
                    let upperWindowSeconds = TimeInterval(RatioEstimator.endGlucoseWindowUpperMinutes * 60)
                    let mealObservations: [MealObservation] = try allImpacts.compactMap { impact in
                        guard let meal = mealById[impact.mealEntryId] else { return nil }

                        let t = meal.timestamp

                        let readings: [SensorGlucose]
                        if impact.isClean {
                            let windowEnd = t.addingTimeInterval(upperWindowSeconds)
                            readings = try SensorGlucose
                                .filter(Column(SensorGlucose.Columns.timestamp.name) >= t)
                                .filter(Column(SensorGlucose.Columns.timestamp.name) <= windowEnd)
                                .order(Column(SensorGlucose.Columns.timestamp.name))
                                .fetchAll(db)
                        } else {
                            readings = []
                        }

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

                    promise(.success(RatioEvidence(tddDays: tddDays, mealObservations: mealObservations, correctionImpacts: correctionImpacts)))
                } catch {
                    promise(.failure(.withError(error)))
                }
            }
        }
    }
}
