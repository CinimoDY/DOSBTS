//
//  DailyDigestMiddleware.swift
//  DOSBTSApp
//

import Combine
import Foundation

func dailyDigestMiddleware() -> Middleware<DirectState, DirectAction> {
    return dailyDigestMiddleware(service: LazyService<ClaudeService>(initialization: {
        ClaudeService()
    }))
}

private func dailyDigestMiddleware(service: LazyService<ClaudeService>) -> Middleware<DirectState, DirectAction> {
    return { state, action, _ in
        switch action {
        case .startup:
            DataStore.shared.createDailyDigestTable()
            return Empty().eraseToAnyPublisher()

        case .setAppState(appState: let appState):
            // Re-trigger digest load if app becomes active and no digest is loaded
            guard appState == .active, state.currentDailyDigest == nil else {
                return Empty().eraseToAnyPublisher()
            }
            return Just(DirectAction.loadDailyDigest(date: Date()))
                .setFailureType(to: DirectError.self)
                .eraseToAnyPublisher()

        case .loadDailyDigest(date: let date):
            guard state.appState == .active else {
                return Just(DirectAction.setDailyDigestError)
                    .setFailureType(to: DirectError.self)
                    .eraseToAnyPublisher()
            }

            let isToday = Calendar.current.isDateInToday(date)

            return Future<DirectAction, DirectError> { promise in
                Task {
                    // For today, always recompute (data is still accumulating).
                    // For past days, use cache if available.
                    if !isToday {
                        if let cached = try? await DataStore.shared.getDailyDigest(date: date).asyncValue() {
                            promise(.success(.setDailyDigest(digest: cached)))
                            return
                        }
                    }

                    // Compute fresh stats from raw data
                    do {
                        let digest = try await DataStore.shared.computeDailyDigest(
                            date: date,
                            alarmLow: state.alarmLow,
                            alarmHigh: state.alarmHigh
                        ).asyncValue()

                        // Save to GRDB cache (outside the read transaction)
                        DataStore.shared.saveDailyDigest(digest)

                        promise(.success(.setDailyDigest(digest: digest)))
                    } catch {
                        DirectLog.error("DailyDigest computation failed: \(error)")
                        promise(.success(.setDailyDigestError))
                    }
                }
            }
            .eraseToAnyPublisher()

        case .setDailyDigest(digest: let digest):
            // After stats are set, load events for timeline display
            guard let digest = digest else {
                return Empty().eraseToAnyPublisher()
            }

            // Load events, then optionally trigger AI insight
            return Future<DirectAction, DirectError> { promise in
                Task {
                    if let events = try? await DataStore.shared.getDailyEvents(date: digest.date).asyncValue() {
                        // First dispatch events, then check AI
                        promise(.success(.setDailyDigestEvents(events: events)))
                    } else {
                        promise(.success(.setDailyDigestEvents(events: DailyDigestEvents(meals: [], insulin: [], exercise: []))))
                    }
                }
            }
            .eraseToAnyPublisher()

        case .setDailyDigestEvents:
            // After events are loaded, check if AI insight should be generated
            guard let digest = state.currentDailyDigest else {
                return Empty().eraseToAnyPublisher()
            }

            // `!dailyDigestInsightLoading` keeps a refresh that lands mid-flight
            // from firing a second, concurrent paid generation — `aiInsight` is
            // still nil until the first one returns, and the events array can
            // now be refreshed independently (adding a journal note does it).
            // The reducer runs before middlewares, so this reads the flag's
            // current value.
            if digest.aiInsight == nil,
               !state.dailyDigestInsightLoading,
               state.aiConsentDailyDigestV2,
               KeychainService.read(key: ClaudeService.keychainKey) != nil {
                return Just(DirectAction.generateDailyDigestInsight(date: digest.date))
                    .setFailureType(to: DirectError.self)
                    .eraseToAnyPublisher()
            }

            return Empty().eraseToAnyPublisher()

        case .generateDailyDigestInsight(date: let date, force: let force):
            guard state.aiConsentDailyDigestV2 else {
                return Empty().eraseToAnyPublisher()
            }

            // If not forced and insight already exists, skip
            if !force, state.currentDailyDigest?.aiInsight != nil {
                return Empty().eraseToAnyPublisher()
            }

            return Future<DirectAction, DirectError> { promise in
                Task {
                    do {
                        // Fetch digest from GRDB, not stale state snapshot (user may have navigated)
                        let digest: DailyDigest
                        if let cached = try? await DataStore.shared.getDailyDigest(date: date).asyncValue() {
                            digest = cached
                        } else {
                            digest = DailyDigest(
                                date: date, tir: 0, tbr: 0, tar: 0, avg: 0, stdev: 0,
                                readings: 0, lowCount: 0, highCount: 0,
                                totalCarbsGrams: 0, totalInsulinUnits: 0,
                                totalExerciseMinutes: 0, mealCount: 0, insulinCount: 0
                            )
                        }

                        // Run GRDB reads concurrently
                        async let eventsTask = DataStore.shared.getDailyEvents(date: date).asyncValue()
                        async let samplesTask = DataStore.shared.getGlucoseSamples(date: date).asyncValue()
                        async let digestsTask = DataStore.shared.getLast7Digests().asyncValue()

                        let events = try await eventsTask
                        let glucoseSamples = try await samplesTask
                        let recentDigests = (try await digestsTask).filter { !Calendar.current.isDate($0.date, inSameDayAs: date) }

                        let insight = try await service.value.generateDigestInsight(
                            digest: digest,
                            events: events,
                            glucoseSamples: glucoseSamples,
                            recentDigests: recentDigests
                        )

                        // Update GRDB cache
                        DataStore.shared.updateDailyDigestInsight(date: date, insight: insight)

                        promise(.success(.setDailyDigestInsight(date: date, insight: insight)))
                    } catch {
                        DirectLog.error("DailyDigest AI insight failed: \(error)")
                        promise(.success(.setDailyDigestInsightError))
                    }
                }
            }
            .eraseToAnyPublisher()

        default:
            break
        }

        return Empty().eraseToAnyPublisher()
    }
}

// MARK: - Future async bridge

private extension Future where Failure == DirectError {
    func asyncValue() async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            var cancellable: AnyCancellable?
            cancellable = self.sink(
                receiveCompletion: { completion in
                    guard !resumed else {
                        cancellable?.cancel()
                        return
                    }
                    switch completion {
                    case .finished:
                        break
                    case .failure(let error):
                        resumed = true
                        continuation.resume(throwing: error)
                    }
                    cancellable?.cancel()
                },
                receiveValue: { value in
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(returning: value)
                }
            )
        }
    }
}
