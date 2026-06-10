//
//  AlarmProfileTests.swift
//  DOSBTSTests
//

import Foundation
import Testing
@testable import DOSBTSApp

private func dateAt(hour: Int, minute: Int) -> Date {
    var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
    components.hour = hour
    components.minute = minute
    components.second = 0
    return Calendar.current.date(from: components) ?? Date()
}

@Suite("AlarmProfile resolution")
struct AlarmProfileResolutionTests {

    // Default schedule: 22:00 → 07:00 (wraps midnight)

    @Test("Day at 14:00 with default schedule")
    func dayMidday() {
        let result = resolveActiveAlarmProfile(
            at: dateAt(hour: 14, minute: 0),
            nightStartHour: 22, nightStartMinute: 0,
            nightEndHour: 7, nightEndMinute: 0
        )
        #expect(result == .day)
    }

    @Test("Night at 22:30 with default schedule")
    func nightAfterStart() {
        let result = resolveActiveAlarmProfile(
            at: dateAt(hour: 22, minute: 30),
            nightStartHour: 22, nightStartMinute: 0,
            nightEndHour: 7, nightEndMinute: 0
        )
        #expect(result == .night)
    }

    @Test("Night at 06:30 with default schedule")
    func nightBeforeEnd() {
        let result = resolveActiveAlarmProfile(
            at: dateAt(hour: 6, minute: 30),
            nightStartHour: 22, nightStartMinute: 0,
            nightEndHour: 7, nightEndMinute: 0
        )
        #expect(result == .night)
    }

    @Test("Day at 07:30 with default schedule")
    func dayAfterEnd() {
        let result = resolveActiveAlarmProfile(
            at: dateAt(hour: 7, minute: 30),
            nightStartHour: 22, nightStartMinute: 0,
            nightEndHour: 7, nightEndMinute: 0
        )
        #expect(result == .day)
    }

    @Test("Boundary at exact start (22:00) is night (inclusive lower bound)")
    func startInclusive() {
        let result = resolveActiveAlarmProfile(
            at: dateAt(hour: 22, minute: 0),
            nightStartHour: 22, nightStartMinute: 0,
            nightEndHour: 7, nightEndMinute: 0
        )
        #expect(result == .night)
    }

    @Test("Boundary at exact end (07:00) is day (exclusive upper bound)")
    func endExclusive() {
        let result = resolveActiveAlarmProfile(
            at: dateAt(hour: 7, minute: 0),
            nightStartHour: 22, nightStartMinute: 0,
            nightEndHour: 7, nightEndMinute: 0
        )
        #expect(result == .day)
    }

    @Test("Midnight wrap 21:00→06:00 night at 23:00")
    func wrapEvening() {
        let result = resolveActiveAlarmProfile(
            at: dateAt(hour: 23, minute: 0),
            nightStartHour: 21, nightStartMinute: 0,
            nightEndHour: 6, nightEndMinute: 0
        )
        #expect(result == .night)
    }

    @Test("Midnight wrap 21:00→06:00 night at 02:00")
    func wrapAfterMidnight() {
        let result = resolveActiveAlarmProfile(
            at: dateAt(hour: 2, minute: 0),
            nightStartHour: 21, nightStartMinute: 0,
            nightEndHour: 6, nightEndMinute: 0
        )
        #expect(result == .night)
    }

    @Test("Midnight wrap 21:00→06:00 day at 06:00 (exclusive)")
    func wrapAtEnd() {
        let result = resolveActiveAlarmProfile(
            at: dateAt(hour: 6, minute: 0),
            nightStartHour: 21, nightStartMinute: 0,
            nightEndHour: 6, nightEndMinute: 0
        )
        #expect(result == .day)
    }

    @Test("Degenerate same-time start==end always returns day")
    func degenerate() {
        let resultMidday = resolveActiveAlarmProfile(
            at: dateAt(hour: 14, minute: 0),
            nightStartHour: 22, nightStartMinute: 0,
            nightEndHour: 22, nightEndMinute: 0
        )
        #expect(resultMidday == .day)

        let resultAtBoundary = resolveActiveAlarmProfile(
            at: dateAt(hour: 22, minute: 0),
            nightStartHour: 22, nightStartMinute: 0,
            nightEndHour: 22, nightEndMinute: 0
        )
        #expect(resultAtBoundary == .day)
    }

    @Test("Degenerate same-time at midnight returns day")
    func degenerateMidnight() {
        let result = resolveActiveAlarmProfile(
            at: dateAt(hour: 0, minute: 0),
            nightStartHour: 0, nightStartMinute: 0,
            nightEndHour: 0, nightEndMinute: 0
        )
        #expect(result == .day)
    }

    @Test("Same-day window 13:00→18:00 returns night at 15:00")
    func sameDayInside() {
        let result = resolveActiveAlarmProfile(
            at: dateAt(hour: 15, minute: 0),
            nightStartHour: 13, nightStartMinute: 0,
            nightEndHour: 18, nightEndMinute: 0
        )
        #expect(result == .night)
    }

    @Test("Same-day window 13:00→18:00 returns day at 12:59")
    func sameDayBefore() {
        let result = resolveActiveAlarmProfile(
            at: dateAt(hour: 12, minute: 59),
            nightStartHour: 13, nightStartMinute: 0,
            nightEndHour: 18, nightEndMinute: 0
        )
        #expect(result == .day)
    }
}

@Suite("DirectState alarm threshold overlay")
struct DirectStateAlarmOverlayTests {

    @Test("alarmHigh resolves to dayAlarmHigh when active profile is day")
    func dayHigh() {
        var state: DirectState = AppState(defaults: makeTestDefaults())
        // Configure a window that's clearly NOT active right now (say, "night" 04:00→04:01 if not midnight)
        // Easier: use degenerate schedule which forces day always.
        state.nightStartHour = 0
        state.nightStartMinute = 0
        state.nightEndHour = 0
        state.nightEndMinute = 0
        state.dayAlarmHigh = 175
        state.nightAlarmHigh = 200
        #expect(state.activeAlarmProfile == .day)
        #expect(state.alarmHigh == 175)
    }

    @Test("alarmLow resolves to dayAlarmLow when active profile is day")
    func dayLow() {
        var state: DirectState = AppState(defaults: makeTestDefaults())
        state.nightStartHour = 0
        state.nightStartMinute = 0
        state.nightEndHour = 0
        state.nightEndMinute = 0
        state.dayAlarmLow = 80
        state.nightAlarmLow = 90
        #expect(state.activeAlarmProfile == .day)
        #expect(state.alarmLow == 80)
    }

    @Test("alarmVolume resolves to dayAlarmVolume when active profile is day")
    func dayVolume() {
        var state: DirectState = AppState(defaults: makeTestDefaults())
        state.nightStartHour = 0
        state.nightStartMinute = 0
        state.nightEndHour = 0
        state.nightEndMinute = 0
        state.dayAlarmVolume = 0.7
        state.nightAlarmVolume = 0.1
        #expect(state.activeAlarmProfile == .day)
        #expect(state.alarmVolume == 0.7)
    }

    @Test("alarmHigh resolves to nightAlarmHigh when active profile is night")
    func nightHigh() {
        var state: DirectState = AppState(defaults: makeTestDefaults())
        // Configure schedule so that "now" is always inside night window: 00:00 → 23:59
        state.nightStartHour = 0
        state.nightStartMinute = 0
        state.nightEndHour = 23
        state.nightEndMinute = 59
        state.dayAlarmHigh = 175
        state.nightAlarmHigh = 200
        // The schedule above misses one minute per day; use a degenerate-near-full window instead.
        // To make night reliably active, set an extremely wide window covering all reachable times.
        // Simpler: skip the time check by asserting the *resolution function* itself is correct
        // (covered above) and verify the overlay reads the right field given a known active profile.
        // Use a schedule that forces night at the current time by reading current hour/min and
        // building a window strictly containing it.
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let h = now.hour ?? 12
        let m = now.minute ?? 0
        // Window [h:m, h:m+2) contains "now" (the wallclock minute we just read).
        state.nightStartHour = h
        state.nightStartMinute = m
        let endTotal = h * 60 + m + 2
        state.nightEndHour = (endTotal / 60) % 24
        state.nightEndMinute = endTotal % 60
        #expect(state.activeAlarmProfile == .night)
        #expect(state.alarmHigh == 200)
        #expect(state.alarmLow == state.nightAlarmLow)
        #expect(state.alarmVolume == state.nightAlarmVolume)
    }
}
