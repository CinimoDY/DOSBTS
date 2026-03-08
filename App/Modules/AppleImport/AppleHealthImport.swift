//
//  AppleHealthImport.swift
//  DOSBTSApp
//

import Combine
import Foundation
import HealthKit

func appleHealthImportMiddleware() -> Middleware<DirectState, DirectAction> {
    return appleHealthImportMiddleware(service: LazyService<AppleHealthImportService>(initialization: {
        AppleHealthImportService()
    }))
}

private func appleHealthImportMiddleware(service: LazyService<AppleHealthImportService>) -> Middleware<DirectState, DirectAction> {
    return { state, action, _ in
        switch action {
        case .requestAppleHealthImportAccess(enabled: let enabled):
            if enabled {
                guard service.value.healthStoreAvailable else {
                    break
                }

                return Future<DirectAction, DirectError> { promise in
                    service.value.requestAccess { granted in
                        if !granted {
                            promise(.failure(.withMessage("HealthKit import access declined")))
                        } else {
                            promise(.success(.setAppleHealthImport(enabled: true)))
                        }
                    }
                }.eraseToAnyPublisher()
            } else {
                return Just(DirectAction.setAppleHealthImport(enabled: false))
                    .setFailureType(to: DirectError.self)
                    .eraseToAnyPublisher()
            }

        case .setAppleHealthImport(enabled: let enabled):
            guard enabled else { break }

            // Trigger initial sync when import is first enabled
            let publisher = PassthroughSubject<DirectAction, DirectError>()
            service.value.syncAll(state: state, publisher: publisher)
            return publisher.eraseToAnyPublisher()

        case .setAppState(appState: let appState):
            guard appState == .active, state.appleHealthImport else {
                break
            }

            guard service.value.healthStoreAvailable else {
                break
            }

            // Foreground refresh — primary sync mechanism
            let publisher = PassthroughSubject<DirectAction, DirectError>()
            service.value.syncAll(state: state, publisher: publisher)
            return publisher.eraseToAnyPublisher()

        case .setSelectedDate(selectedDate: _):
            guard state.appleHealthImport else {
                break
            }

            guard service.value.healthStoreAvailable else {
                break
            }

            // Re-query heart rate for the visible date range
            let publisher = PassthroughSubject<DirectAction, DirectError>()
            service.value.queryHeartRate(state: state, publisher: publisher)
            return publisher.eraseToAnyPublisher()

        default:
            break
        }

        return Empty().eraseToAnyPublisher()
    }
}

// MARK: - AppleHealthImportService

private class AppleHealthImportService {
    // MARK: Lifecycle

    init() {
        DirectLog.info("Create AppleHealthImportService")
    }

    // MARK: Internal

    var healthStoreAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private let healthStore = HKHealthStore()
    private var isSyncing = false

    private var readPermissions: Set<HKObjectType> {
        Set([
            HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)!,
            HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
            HKObjectType.quantityType(forIdentifier: .dietaryProtein)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.workoutType(),
        ])
    }

    func requestAccess(completionHandler: @escaping (_ granted: Bool) -> Void) {
        healthStore.requestAuthorization(toShare: nil, read: readPermissions) { granted, error in
            if let error = error {
                DirectLog.error("HealthKit import authorization error: \(error.localizedDescription)")
            }
            completionHandler(granted)
        }
    }

    // MARK: - Sync All

    func syncAll(state: DirectState, publisher: PassthroughSubject<DirectAction, DirectError>) {
        guard !isSyncing else {
            publisher.send(completion: .finished)
            return
        }
        isSyncing = true

        let dateRange = dateInterval(for: state)
        let existingMeals = state.mealEntryValues
        let existingExercises = state.exerciseEntryValues
        let ownBundleID = Bundle.main.bundleIdentifier ?? ""
        let date = state.selectedDate ?? Date()

        Task {
            defer {
                self.isSyncing = false
                publisher.send(completion: .finished)
            }

            if #available(iOS 15.4, *) {
                // Nutrition sync
                do {
                    let meals = try await fetchNutritionSamples(dateRange: dateRange, existingMeals: existingMeals, ownBundleID: ownBundleID)
                    if !meals.isEmpty {
                        publisher.send(.addMealEntry(mealEntryValues: meals))
                    }
                } catch {
                    DirectLog.error("HealthKit nutrition sync error: \(error.localizedDescription)")
                }

                // Exercise sync
                do {
                    let exercises = try await fetchExerciseSamples(dateRange: dateRange, existingExercises: existingExercises, ownBundleID: ownBundleID)
                    if !exercises.isEmpty {
                        publisher.send(.addExerciseEntry(exerciseEntryValues: exercises))
                    }
                } catch {
                    DirectLog.error("HealthKit exercise sync error: \(error.localizedDescription)")
                }
            }

            // Heart rate (uses HKStatisticsCollectionQuery, available since iOS 8)
            do {
                let series = try await fetchHourlyHeartRate(for: date)
                publisher.send(.setHeartRateSeries(heartRateSeries: series))
            } catch {
                DirectLog.error("HealthKit heart rate query error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Heart Rate Only

    func queryHeartRate(state: DirectState, publisher: PassthroughSubject<DirectAction, DirectError>) {
        let date = state.selectedDate ?? Date()

        Task {
            defer { publisher.send(completion: .finished) }

            do {
                let series = try await fetchHourlyHeartRate(for: date)
                publisher.send(.setHeartRateSeries(heartRateSeries: series))
            } catch {
                DirectLog.error("HealthKit heart rate query error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private: Nutrition Fetch

    @available(iOS 15.4, *)
    private func fetchNutritionSamples(dateRange: DateInterval, existingMeals: [MealEntry], ownBundleID: String) async throws -> [MealEntry] {
        let carbType = HKQuantityType(.dietaryCarbohydrates)
        let predicate = HKQuery.predicateForSamples(withStart: dateRange.start, end: dateRange.end)

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: carbType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await descriptor.result(for: healthStore)

        // Filter out our own exports (bundle ID dedup)
        let externalSamples = samples.filter { sample in
            sample.sourceRevision.source.bundleIdentifier != ownBundleID
        }

        // Build set of existing sync IDs for dedup
        let existingIDs = Set(existingMeals.map { $0.id.uuidString })

        var meals: [MealEntry] = []
        for sample in externalSamples {
            // Skip if we already have this sample via sync identifier
            if let syncID = sample.metadata?[HKMetadataKeySyncIdentifier] as? String,
               existingIDs.contains(syncID) {
                continue
            }

            let carbs = sample.quantity.doubleValue(for: .gram())

            // Skip if timestamp + carbs fuzzy match with existing entry (within 5 minutes)
            let sampleDate = sample.startDate
            let isDuplicate = existingMeals.contains { existing in
                abs(existing.timestamp.timeIntervalSince(sampleDate)) < 300
                    && existing.carbsGrams != nil
                    && abs(existing.carbsGrams! - carbs) < 0.1
            }
            if isDuplicate { continue }

            let sourceName = sample.sourceRevision.source.name

            meals.append(MealEntry(
                timestamp: sample.startDate,
                mealDescription: sourceName,
                carbsGrams: carbs
            ))
        }

        return meals
    }

    // MARK: - Private: Exercise Fetch

    @available(iOS 15.4, *)
    private func fetchExerciseSamples(dateRange: DateInterval, existingExercises: [ExerciseEntry], ownBundleID: String) async throws -> [ExerciseEntry] {
        let predicate = HKQuery.predicateForSamples(withStart: dateRange.start, end: dateRange.end)

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let workouts = try await descriptor.result(for: healthStore)

        let externalWorkouts = workouts.filter { $0.sourceRevision.source.bundleIdentifier != ownBundleID }

        let existingStarts = Set(existingExercises.map { $0.startTime })

        var exercises: [ExerciseEntry] = []
        for workout in externalWorkouts {
            let roundedStart = workout.startDate.toRounded(on: 1, .minute)
            if existingStarts.contains(roundedStart) { continue }

            let duration = workout.duration / 60.0
            var calories: Double? = nil
            if #available(iOS 16.0, *) {
                calories = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
                    .sumQuantity()?.doubleValue(for: .kilocalorie())
            }
            let sourceName = workout.sourceRevision.source.name

            exercises.append(ExerciseEntry(
                startTime: workout.startDate,
                endTime: workout.endDate,
                activityType: workout.workoutActivityType.displayName,
                durationMinutes: duration,
                activeCalories: calories,
                source: sourceName
            ))
        }

        return exercises
    }

    // MARK: - Private: Heart Rate

    private func fetchHourlyHeartRate(for date: Date) async throws -> [(Date, Double)] {
        let heartRateType = HKQuantityType(.heartRate)
        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfDay = startOfDay.addingTimeInterval(86400)

        let query = HKStatisticsCollectionQuery(
            quantityType: heartRateType,
            quantitySamplePredicate: HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay),
            options: .discreteAverage,
            anchorDate: startOfDay,
            intervalComponents: DateComponents(hour: 1)
        )

        return try await withCheckedThrowingContinuation { continuation in
            query.initialResultsHandler = { _, results, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                var hourlyRates: [(Date, Double)] = []
                results?.enumerateStatistics(from: startOfDay, to: endOfDay) { statistics, _ in
                    if let avg = statistics.averageQuantity() {
                        hourlyRates.append((statistics.startDate,
                                            avg.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))))
                    }
                }
                continuation.resume(returning: hourlyRates)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Helpers

    private func dateInterval(for state: DirectState) -> DateInterval {
        if let selectedDate = state.selectedDate,
           let nextDate = Calendar.current.date(byAdding: .day, value: +1, to: selectedDate) {
            return DateInterval(start: selectedDate.startOfDay, end: nextDate.startOfDay)
        } else {
            let end = Date()
            let start = end.addingTimeInterval(-Double(DirectConfig.lastChartHours) * 3600)
            return DateInterval(start: start, end: end)
        }
    }
}

// MARK: - HKWorkoutActivityType + displayName

extension HKWorkoutActivityType {
    var displayName: String {
        switch self {
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .walking: return "Walking"
        case .swimming: return "Swimming"
        case .hiking: return "Hiking"
        case .yoga: return "Yoga"
        case .functionalStrengthTraining: return "Strength"
        case .traditionalStrengthTraining: return "Strength"
        case .highIntensityIntervalTraining: return "HIIT"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .stairClimbing: return "Stairs"
        case .dance: return "Dance"
        case .coreTraining: return "Core"
        case .cooldown: return "Cooldown"
        case .mixedCardio: return "Cardio"
        case .pilates: return "Pilates"
        default: return "Exercise"
        }
    }
}
