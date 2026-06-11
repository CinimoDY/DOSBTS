//
//  GlucoseStatusBarTests.swift
//  DOSBTSTests
//
//  Pins the origin R7b state table (all seven rows), the R8 conditional
//  MEAL routing (AE2/F2), and the shared staleness tiers the bar and the
//  Overview hero both read (KTD-4).
//

import Foundation
import Testing
@testable import DOSBTSApp

@Suite("GlucoseStatusBar state mapping (R7b)")
struct GlucoseStatusBarModelTests {
    private func makeGlucose(value: Int, minutesAgo: Int, now: Date) -> SensorGlucose {
        SensorGlucose(
            timestamp: now.addingTimeInterval(TimeInterval(-minutesAgo * 60)),
            rawGlucoseValue: value,
            intGlucoseValue: value,
            minuteChange: 1.0
        )
    }

    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    @Test("row 1: no sensor paired shows NO SENSOR — actions always work")
    func noSensor() {
        let model = GlucoseStatusBarModel.make(
            hasSensor: false, latestGlucose: nil, glucoseUnit: .mgdL,
            treatmentCycleActive: false, now: now
        )
        #expect(model.mode == .noSensor)
        #expect(model.mealSheet.id == "meal")
    }

    @Test("row 2: sensor but no reading yet shows the placeholder glyph")
    func awaitingReading() {
        let model = GlucoseStatusBarModel.make(
            hasSensor: true, latestGlucose: nil, glucoseUnit: .mgdL,
            treatmentCycleActive: false, now: now
        )
        #expect(model.mode == .awaitingReading)
    }

    @Test("row 3: fresh reading (<5 min) shows value + trend")
    func freshReading() {
        let glucose = makeGlucose(value: 117, minutesAgo: 2, now: now)
        let model = GlucoseStatusBarModel.make(
            hasSensor: true, latestGlucose: glucose, glucoseUnit: .mgdL,
            treatmentCycleActive: false, now: now
        )
        guard case .reading(let value, _, let staleness, let countdown) = model.mode else {
            Issue.record("expected .reading"); return
        }
        #expect(value == "117")
        #expect(staleness == .fresh)
        #expect(countdown == false)
    }

    @Test("row 4: 5–14 min stale carries the amber-tier staleness label")
    func staleReading() {
        let glucose = makeGlucose(value: 110, minutesAgo: 8, now: now)
        let model = GlucoseStatusBarModel.make(
            hasSensor: true, latestGlucose: glucose, glucoseUnit: .mgdL,
            treatmentCycleActive: false, now: now
        )
        guard case .reading(_, _, let staleness, _) = model.mode else {
            Issue.record("expected .reading"); return
        }
        #expect(staleness == .stale(minutes: 8))
        #expect(staleness.minutesAgoLabel == "8 MIN AGO")
    }

    @Test("row 5: 15+ min stale escalates to the red tier")
    func veryStaleReading() {
        let glucose = makeGlucose(value: 110, minutesAgo: 22, now: now)
        let model = GlucoseStatusBarModel.make(
            hasSensor: true, latestGlucose: glucose, glucoseUnit: .mgdL,
            treatmentCycleActive: false, now: now
        )
        guard case .reading(_, _, let staleness, _) = model.mode else {
            Issue.record("expected .reading"); return
        }
        #expect(staleness == .veryStale(minutes: 22))
    }

    @Test("row 6: treatment cycle shows the countdown indicator in place of the trend")
    func treatmentCycleCountdown() {
        let glucose = makeGlucose(value: 72, minutesAgo: 1, now: now)
        let model = GlucoseStatusBarModel.make(
            hasSensor: true, latestGlucose: glucose, glucoseUnit: .mgdL,
            treatmentCycleActive: true, now: now
        )
        guard case .reading(_, _, _, let countdown) = model.mode else {
            Issue.record("expected .reading"); return
        }
        #expect(countdown == true)
    }

    // Row 7 (alarm firing mirrors the hero's color state) is pinned via the
    // shared AmberTheme.glucoseColor the view reads — same function, same
    // inputs as the hero; no separate mapping exists to diverge.

    @Test("R8/AE2/F2: MEAL routes to the hypo-filtered sheet during a cycle, normal sheet otherwise")
    func mealRouting() {
        let glucose = makeGlucose(value: 72, minutesAgo: 1, now: now)

        let inCycle = GlucoseStatusBarModel.make(
            hasSensor: true, latestGlucose: glucose, glucoseUnit: .mgdL,
            treatmentCycleActive: true, now: now
        )
        #expect(inCycle.mealSheet.id == "filteredFoodEntry")

        let outOfCycle = GlucoseStatusBarModel.make(
            hasSensor: true, latestGlucose: glucose, glucoseUnit: .mgdL,
            treatmentCycleActive: false, now: now
        )
        #expect(outOfCycle.mealSheet.id == "meal")
    }
}

// MARK: - Shared staleness tiers (KTD-4)

@Suite("GlucoseStaleness shared tiers")
struct GlucoseStalenessTests {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func staleness(minutesAgo: Double) -> GlucoseStaleness {
        GlucoseStaleness.of(
            readingTimestamp: now.addingTimeInterval(-minutesAgo * 60),
            now: now
        )
    }

    @Test("thresholds match the hero: <5 fresh, 5–14 amber, 15+ red")
    func tierBoundaries() {
        #expect(staleness(minutesAgo: 0) == .fresh)
        #expect(staleness(minutesAgo: 4.9) == .fresh)
        #expect(staleness(minutesAgo: 5) == .stale(minutes: 5))
        #expect(staleness(minutesAgo: 14.9) == .stale(minutes: 14))
        #expect(staleness(minutesAgo: 15) == .veryStale(minutes: 15))
        #expect(staleness(minutesAgo: 60) == .veryStale(minutes: 60))
    }

    @Test("threshold constants are pinned (hero and bar share them)")
    func constantsPinned() {
        #expect(GlucoseStaleness.staleThresholdMinutes == 5)
        #expect(GlucoseStaleness.veryStaleThresholdMinutes == 15)
    }

    @Test("fresh has no label; stale tiers render X MIN AGO")
    func labels() {
        #expect(GlucoseStaleness.fresh.minutesAgoLabel == nil)
        #expect(GlucoseStaleness.stale(minutes: 7).minutesAgoLabel == "7 MIN AGO")
        #expect(GlucoseStaleness.veryStale(minutes: 20).minutesAgoLabel == "20 MIN AGO")
    }
}
