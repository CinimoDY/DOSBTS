//
//  SensorTests.swift
//  DOSBTSTests
//

import Foundation
import Testing
@testable import DOSBTSApp

// MARK: - Sensor Lifecycle Computed Properties

@Suite("Sensor warmup and lifetime")
struct SensorLifecycleTests {

    private func makeSensor(age: Int, lifetime: Int, warmupTime: Int = 60) -> Sensor {
        Sensor(
            family: .libre2,
            type: .libre2EU,
            region: .european,
            serial: "TEST123",
            state: .ready,
            age: age,
            lifetime: lifetime,
            warmupTime: warmupTime
        )
    }

    @Test("remainingWarmupTime returns time when age <= warmupTime")
    func warmupRemaining() {
        let sensor = makeSensor(age: 30, lifetime: 20160, warmupTime: 60)
        #expect(sensor.remainingWarmupTime == 30)
    }

    @Test("remainingWarmupTime is nil when age > warmupTime")
    func warmupComplete() {
        let sensor = makeSensor(age: 120, lifetime: 20160, warmupTime: 60)
        #expect(sensor.remainingWarmupTime == nil)
    }

    @Test("remainingWarmupTime at exact warmup boundary is zero")
    func warmupExactBoundary() {
        let sensor = makeSensor(age: 60, lifetime: 20160, warmupTime: 60)
        #expect(sensor.remainingWarmupTime == 0)
    }

    @Test("remainingLifetime is lifetime minus age")
    func remainingLifetime() {
        let sensor = makeSensor(age: 5000, lifetime: 20160)
        #expect(sensor.remainingLifetime == 15160)
    }

    @Test("remainingLifetime is zero when age exceeds lifetime")
    func remainingLifetimeExpired() {
        let sensor = makeSensor(age: 25000, lifetime: 20160)
        #expect(sensor.remainingLifetime == 0)
    }

    @Test("elapsedLifetime equals lifetime minus remainingLifetime")
    func elapsedLifetime() {
        let sensor = makeSensor(age: 5000, lifetime: 20160)
        #expect(sensor.elapsedLifetime == 5000)
    }

    @Test("elapsedLifetime equals lifetime when sensor expired")
    func elapsedLifetimeExpired() {
        let sensor = makeSensor(age: 25000, lifetime: 20160)
        #expect(sensor.elapsedLifetime == 20160)
    }

    @Test("endTimestamp is nil when startTimestamp is nil")
    func endTimestampNil() {
        let sensor = makeSensor(age: 100, lifetime: 20160)
        #expect(sensor.endTimestamp == nil)
    }

    @Test("endTimestamp is startTimestamp plus lifetime minutes")
    func endTimestampComputed() {
        var sensor = makeSensor(age: 100, lifetime: 20160)
        let start = Date()
        sensor.startTimestamp = start

        let expected = Calendar.current.date(byAdding: .minute, value: 20160, to: start)
        #expect(sensor.endTimestamp == expected)
    }
}

// MARK: - Compact remaining-time formatting (Overview sensor line)

@Suite("Remaining-time compact formatting")
struct InTimeCompactTests {

    @Test("multi-day lifetime shows days and hours, never minutes-only")
    func multiDayKeepsDaysAndHours() {
        // 3d 2h 18min = 3*1440 + 2*60 + 18 = 4458 minutes.
        // Regression guard for the Overview truncation bug: this must surface
        // the days/hours, not collapse to "18min".
        let minutes = 3 * 1440 + 2 * 60 + 18
        #expect(minutes.inTimeCompact == "3d 2h")
    }

    @Test("sub-day lifetime keeps hour + minute precision")
    func subDayKeepsHoursAndMinutes() {
        let minutes = 2 * 60 + 18
        #expect(minutes.inTimeCompact == "2h 18min")
    }

    @Test("sub-hour lifetime shows minutes only")
    func subHourShowsMinutes() {
        #expect(18.inTimeCompact == "18min")
    }
}
