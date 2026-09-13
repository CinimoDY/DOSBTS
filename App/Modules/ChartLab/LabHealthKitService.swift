//
//  LabHealthKitService.swift
//  DOSBTSApp
//
//  Chart Lab P1 (DMNC-1506) — the HealthKit half of the window loader: sleep
//  stages, and heart rate over an ARBITRARY interval (the shipping importer's
//  heart-rate query is day-scoped, which cannot answer a window that crosses
//  midnight).
//
//  Its own `HKHealthStore` on purpose: `AppleHealthImportService` is a
//  `private class` created inside `appleHealthImportMiddleware`'s own
//  `LazyService`, so there is no instance another middleware can reach.
//  Multiple health stores are supported and cheap.
//
//  What HealthKit will and will not tell us:
//  `authorizationStatus(for:)` reports the SHARE status. For a read-only type it
//  is `.notDetermined` until the user has been asked, and `.sharingDenied`
//  afterwards whether they granted the read or refused it — HealthKit never
//  reveals a read denial. So `.notDetermined` is the only honest `n/a`; after
//  the prompt, an empty result is reported as empty, because that is genuinely
//  all we know.
//

import Foundation
import HealthKit

final class LabHealthKitService {
    // MARK: Lifecycle

    init() {
        DirectLog.info("Create LabHealthKitService")
    }

    // MARK: Internal

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// Ask once for the lab's read types, but only when the caller says the
    /// user has already opted into Apple Health — the lab completes a consent
    /// the user gave, it never opens a new one.
    func requestAccessIfNeeded() async {
        guard isAvailable else { return }

        let pending = Self.readTypes.filter { healthStore.authorizationStatus(for: $0) == .notDetermined }
        guard !pending.isEmpty else { return }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: Set(pending))
        } catch {
            DirectLog.error("Chart Lab HealthKit authorization error: \(error.localizedDescription)")
        }
    }

    func availability(for type: HKObjectType) -> LabStreamAvailability {
        guard isAvailable else { return .unavailable }
        return healthStore.authorizationStatus(for: type) == .notDetermined ? .unavailable : .available
    }

    var sleepAvailability: LabStreamAvailability {
        availability(for: Self.sleepType)
    }

    var heartRateAvailability: LabStreamAvailability {
        availability(for: Self.heartRateType)
    }

    /// Every sleep-analysis sample overlapping the interval, newest last.
    func fetchSleep(in interval: DateInterval) async throws -> [SleepSample] {
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: Self.sleepType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )

        let samples = try await descriptor.result(for: healthStore)
        return samples.map {
            SleepSample(
                start: $0.startDate,
                end: $0.endDate,
                stage: SleepSample.Stage(healthKitValue: $0.value)
            )
        }
    }

    /// Hourly average heart rate across an arbitrary interval — the shipping
    /// `fetchHourlyHeartRate(for date:)` anchors on a calendar day and cannot
    /// span midnight.
    func fetchHourlyHeartRate(in interval: DateInterval) async throws -> [HeartRateSample] {
        let query = HKStatisticsCollectionQuery(
            quantityType: Self.heartRateType,
            quantitySamplePredicate: HKQuery.predicateForSamples(withStart: interval.start, end: interval.end),
            options: .discreteAverage,
            anchorDate: interval.start,
            intervalComponents: DateComponents(hour: 1)
        )

        return try await withCheckedThrowingContinuation { continuation in
            // `initialResultsHandler` fires exactly once for a non-long-running
            // query, but the guard costs nothing and a double-resume traps.
            var resumed = false

            query.initialResultsHandler = { _, results, error in
                guard !resumed else { return }
                resumed = true

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                var samples: [HeartRateSample] = []
                results?.enumerateStatistics(from: interval.start, to: interval.end) { statistics, _ in
                    if let average = statistics.averageQuantity() {
                        samples.append(HeartRateSample(
                            time: statistics.startDate,
                            bpm: average.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                        ))
                    }
                }
                continuation.resume(returning: samples)
            }

            healthStore.execute(query)
        }
    }

    // MARK: Private

    private static let sleepType = HKCategoryType(.sleepAnalysis)
    private static let heartRateType = HKQuantityType(.heartRate)
    private static let readTypes: [HKObjectType] = [sleepType, heartRateType]

    private let healthStore = HKHealthStore()
}
