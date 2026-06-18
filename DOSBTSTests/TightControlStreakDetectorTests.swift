//
//  TightControlStreakDetectorTests.swift
//  DOSBTSTests
//
//  U2 (DMNC-772): the pure tight-control detection engine. Written test-first.
//  Covers accrual, the 2h boundary, gap breaks (R3), hysteresis re-arm (R4),
//  dedup/idempotent replay (R8), batch sorting, and clock/now guards.
//

import Foundation
import Testing
@testable import DOSBTSApp

// Fixed, minute-aligned clock (1_700_000_400 = 28_333_340 × 60) so reading
// timestamps — which SensorGlucose rounds to the minute — stay exact.
private let base = Date(timeIntervalSince1970: 1_700_000_400)

private func minutes(_ m: Int) -> TimeInterval { TimeInterval(m * 60) }

/// Readings of `value` mg/dL every `intervalMin` minutes spanning `spanMinutes`,
/// with the LAST reading at `end`. Returned newest-first so the engine's internal
/// sort is exercised. Count = spanMinutes / intervalMin + 1.
private func run(spanMinutes: Int, intervalMin: Int = 5, value: Int = 100, endingAt end: Date) -> [SensorGlucose] {
    var out: [SensorGlucose] = []
    var elapsed = 0
    while elapsed <= spanMinutes {
        let timestamp = end.addingTimeInterval(-minutes(elapsed))
        out.append(SensorGlucose(timestamp: timestamp, rawGlucoseValue: value, intGlucoseValue: value))
        elapsed += intervalMin
    }
    return out
}

private func reading(_ value: Int, at timestamp: Date) -> SensorGlucose {
    SensorGlucose(timestamp: timestamp, rawGlucoseValue: value, intGlucoseValue: value)
}

private func evaluate(_ readings: [SensorGlucose], marker: Date? = nil, now: Date) -> (shouldCelebrate: Bool, celebratedStreakStart: Date?) {
    TightControlStreakDetector.evaluate(readings: readings, lastCelebratedStreakStart: marker, now: now)
}

@Suite("Tight-control streak detector (DMNC-772)")
struct TightControlStreakDetectorTests {

    // MARK: Happy path / boundary

    @Test("AE1: a 2h continuous in-band run ending now celebrates, returning the run's start")
    func celebratesOnTwoHourRun() {
        let result = evaluate(run(spanMinutes: 120, endingAt: base), now: base.addingTimeInterval(30))
        #expect(result.shouldCelebrate)
        #expect(result.celebratedStreakStart == base.addingTimeInterval(-minutes(120)))
    }

    @Test("exactly 2h fires; 1h59m does not")
    func boundary() {
        let now = base.addingTimeInterval(30)
        #expect(evaluate(run(spanMinutes: 120, endingAt: base), now: now).shouldCelebrate)
        #expect(!evaluate(run(spanMinutes: 119, intervalMin: 1, endingAt: base), now: now).shouldCelebrate)
    }

    @Test("empty history does not celebrate")
    func emptyNoFire() {
        let result = evaluate([], now: base)
        #expect(!result.shouldCelebrate)
        #expect(result.celebratedStreakStart == nil)
    }

    @Test("an out-of-band latest reading does not celebrate even after a long in-band run")
    func outOfBandLatest() {
        var readings = run(spanMinutes: 120, endingAt: base.addingTimeInterval(-minutes(5)))
        readings.append(reading(150, at: base))
        #expect(!evaluate(readings, now: base.addingTimeInterval(30)).shouldCelebrate)
    }

    // MARK: Sorting

    @Test("scrambled (unsorted) readings still detect the run")
    func unsortedHandled() {
        var readings = run(spanMinutes: 120, endingAt: base)
        readings.shuffle()
        #expect(evaluate(readings, now: base.addingTimeInterval(30)).shouldCelebrate)
    }

    // MARK: Gap (R3)

    @Test("AE4: a 40-min gap breaks the run — resumed 90 min does not re-accrue to 2h")
    func gapBreaksRun() {
        var readings = run(spanMinutes: 90, endingAt: base.addingTimeInterval(-minutes(130)))
        readings += run(spanMinutes: 90, endingAt: base)
        #expect(!evaluate(readings, now: base.addingTimeInterval(30)).shouldCelebrate)
    }

    // MARK: Dedup / idempotent replay (R8)

    @Test("AE5-engine: re-evaluating with the stored marker is idempotent (no re-fire)")
    func idempotentReplay() {
        let readings = run(spanMinutes: 120, endingAt: base)
        let now = base.addingTimeInterval(30)
        let first = evaluate(readings, now: now)
        #expect(first.shouldCelebrate)
        let second = evaluate(readings, marker: first.celebratedStreakStart, now: now)
        #expect(!second.shouldCelebrate)
    }

    // MARK: Hysteresis re-arm (R4)

    @Test("AE2: after a fire, a single 121 blip does not re-arm — no re-fire even after a fresh 2h run")
    func singleBlipDoesNotRearm() {
        let celebratedStart = base.addingTimeInterval(-minutes(320))
        var readings = run(spanMinutes: 120, endingAt: base.addingTimeInterval(-minutes(200)))
        readings.append(reading(121, at: base.addingTimeInterval(-minutes(150))))
        readings += run(spanMinutes: 120, endingAt: base)
        #expect(!evaluate(readings, marker: celebratedStart, now: base.addingTimeInterval(30)).shouldCelebrate)
    }

    @Test("AE3: after a fire, >=2 beyond-margin readings re-arm — a fresh 2h run fires again")
    func beyondMarginRearms() {
        let celebratedStart = base.addingTimeInterval(-minutes(320))
        var readings = run(spanMinutes: 120, endingAt: base.addingTimeInterval(-minutes(200)))
        readings.append(reading(130, at: base.addingTimeInterval(-minutes(160))))
        readings.append(reading(130, at: base.addingTimeInterval(-minutes(155))))
        readings += run(spanMinutes: 120, endingAt: base)
        let result = evaluate(readings, marker: celebratedStart, now: base.addingTimeInterval(30))
        #expect(result.shouldCelebrate)
        #expect(result.celebratedStreakStart == base.addingTimeInterval(-minutes(120)))
    }

    // MARK: Clock / now guards

    @Test("clock moved backward (now precedes the run start) does not celebrate")
    func clockBackward() {
        let readings = run(spanMinutes: 120, endingAt: base)
        #expect(!evaluate(readings, now: base.addingTimeInterval(-minutes(180))).shouldCelebrate)
    }

    @Test("a historical run that does not extend to now does not celebrate")
    func historicalWindow() {
        let readings = run(spanMinutes: 120, endingAt: base.addingTimeInterval(-minutes(480)))
        #expect(!evaluate(readings, now: base).shouldCelebrate)
    }
}
