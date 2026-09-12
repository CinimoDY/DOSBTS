//
//  ChartLabPatternsTests.swift
//  DOSBTSTests
//
//  Chart Lab P4 (DMNC-1503 / DMNC-1500) — `LAB: PATTERNS`: the personal hourly
//  band under today. Pins the additive p5/p95/days extension of `HourlyPattern`,
//  the transient evidence state + its day cap, the pure pattern analysis
//  (out-of-band hours, the pattern hour, the same-hour drill) and the band
//  geometry + copy the chart arm renders.
//
//  Everything here is pure — no view instantiation, no GRDB, no store.
//

import Foundation
import Testing
@testable import DOSBTSApp

// MARK: - Shared helpers

// Copies of the file-private helpers in DirectReducerTests.swift (they are
// file-private there, so every test file carries its own pair).
// `makeTestDefaults()` itself is target-wide.
private func makeState() -> AppState {
    AppState(defaults: makeTestDefaults())
}

private func reduce(_ state: inout DirectState, _ action: DirectAction) {
    directReducer(state: &state, action: action)
}

private var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    return calendar
}

/// 15 June 2026, UTC.
private func date(day: Int = 15, hour: Int, minute: Int = 0) throws -> Date {
    try #require(utcCalendar.date(from: DateComponents(year: 2026, month: 6, day: day, hour: hour, minute: minute)))
}

private func reading(day: Int = 15, hour: Int, minute: Int = 0, _ value: Int) throws -> SensorGlucose {
    SensorGlucose(timestamp: try date(day: day, hour: hour, minute: minute), rawGlucoseValue: value, intGlucoseValue: value)
}

/// A full hour of readings, one a minute, all the same value.
private func flatHour(day: Int = 15, hour: Int, _ value: Int, minutes: Int = 12) throws -> [SensorGlucose] {
    try (0 ..< minutes).map { try reading(day: day, hour: hour, minute: $0 * (60 / minutes), value) }
}

// MARK: - Hourly p5/p95

@Suite("Hourly p5/p95")
struct HourlyPercentileTests {
    @Test("a 40-value hour: p5/p95 match hand-computed type-7 values")
    func fortyValues() throws {
        // 100...139, one reading a minute in hour 11.
        let readings = try (0 ..< 40).map { try reading(hour: 11, minute: $0, 100 + $0) }
        let patterns = ClinicReportBuilder.hourlyPatterns(from: readings, calendar: utcCalendar)
        let hour = patterns[11]

        // n = 40 → rank = p × 39.
        // p05 → 1.95 → 101 + 0.95 = 101.95 → 102
        // p25 → 9.75 → 109 + 0.75 = 109.75 → 110
        // p50 → 19.5 → 119 + 0.5  = 119.5  → 120
        // p75 → 29.25 → 129 + 0.25 = 129.25 → 129
        // p95 → 37.05 → 137 + 0.05 = 137.05 → 137
        #expect(hour.p5 == 102)
        #expect(hour.p25 == 110)
        #expect(hour.median == 120)
        #expect(hour.p75 == 129)
        #expect(hour.p95 == 137)
        #expect(hour.readings == 40)
    }

    @Test("a single value: p5 == p95 == that value")
    func singleValue() throws {
        let patterns = ClinicReportBuilder.hourlyPatterns(from: [try reading(hour: 3, 142)], calendar: utcCalendar)
        #expect(patterns[3].p5 == 142)
        #expect(patterns[3].p95 == 142)
        #expect(patterns[3].median == 142)
        #expect(patterns[3].days == 1)
    }

    @Test("an empty hour: nil quantiles and days == 0")
    func emptyHour() {
        let patterns = ClinicReportBuilder.hourlyPatterns(from: [], calendar: utcCalendar)
        #expect(patterns.count == 24)
        #expect(patterns.allSatisfy { $0.p5 == nil && $0.p95 == nil && $0.days == 0 })
    }

    @Test("days counts DISTINCT calendar days, not readings")
    func distinctDays() throws {
        // Three readings in hour 7 on two days — 3 readings, 2 days.
        let readings = [
            try reading(day: 15, hour: 7, minute: 0, 100),
            try reading(day: 15, hour: 7, minute: 30, 110),
            try reading(day: 16, hour: 7, minute: 0, 120),
        ]
        let patterns = ClinicReportBuilder.hourlyPatterns(from: readings, calendar: utcCalendar)
        #expect(patterns[7].readings == 3)
        #expect(patterns[7].days == 2)
    }

    @Test("the compatibility initializer keeps the clinic report's call shape")
    func compatibilityInit() {
        let row = HourlyPattern(hour: 4, median: 120, p25: 100, p75: 140, readings: 12)
        #expect(row.p5 == nil)
        #expect(row.p95 == nil)
        #expect(row.days == 0)
    }
}

// MARK: - Lab patterns state

@Suite("Lab patterns state")
struct LabPatternsStateTests {
    @Test("setLabPatterns stores and clears the transient evidence")
    func setAndClear() throws {
        var state: DirectState = makeState()
        #expect(state.labPatterns == nil)

        let evidence = LabPatternEvidence(
            days: 30,
            hourly: ClinicReportBuilder.hourlyPatterns(from: [], calendar: utcCalendar),
            readings: [try reading(hour: 9, 120)],
            period: DateInterval(start: try date(hour: 0), end: try date(hour: 23))
        )
        reduce(&state, .setLabPatterns(evidence: evidence))
        #expect(state.labPatterns == evidence)
        #expect(state.labPatterns?.hourly.count == 24)

        reduce(&state, .setLabPatterns(evidence: nil))
        #expect(state.labPatterns == nil)
    }

    @Test("the look-back is capped at 90 days — the ALL chip must not read 9999 days")
    func daysCap() {
        #expect(LabPatternEvidence.maxDays == 90)
        #expect(LabPatternEvidence.cappedDays(7) == 7)
        #expect(LabPatternEvidence.cappedDays(30) == 30)
        #expect(LabPatternEvidence.cappedDays(90) == 90)
        #expect(LabPatternEvidence.cappedDays(9999) == 90)
        #expect(LabPatternEvidence.cappedDays(0) == 1)
        #expect(LabPatternEvidence.cappedDays(-3) == 1)
    }
}

// MARK: - Pattern analysis

@Suite("Pattern analysis")
struct PatternAnalysisTests {
    /// A band where every hour has 27 days behind it: 100–200, median 150.
    private func band(days: Int = 27, p25: Int = 120, median: Int = 150, p75: Int = 180) -> [HourlyPattern] {
        (0 ..< 24).map { hour in
            HourlyPattern(
                hour: hour,
                median: median,
                p25: p25,
                p75: p75,
                readings: days * 12,
                p5: 90,
                p95: 220,
                days: days
            )
        }
    }

    @Test("today above p75 at 11:00 → one out-of-band hour with the signed delta")
    func aboveBand() throws {
        let today = try flatHour(hour: 11, 218)
        let hours = PatternAnalysis.outOfBand(today: today, hourly: band(), calendar: utcCalendar)

        #expect(hours.count == 1)
        let hit = try #require(hours.first)
        #expect(hit.hour == 11)
        #expect(hit.todayMedian == 218)
        #expect(hit.usualMedian == 150)
        #expect(hit.deltaVsUsual == 68)
        #expect(hit.days == 27)
        #expect(hit.hourStart == (try date(hour: 11)))
    }

    @Test("today below p25 flags with a negative delta")
    func belowBand() throws {
        let today = try flatHour(hour: 4, 90)
        let hours = PatternAnalysis.outOfBand(today: today, hourly: band(), calendar: utcCalendar)
        #expect(hours.map(\.hour) == [4])
        #expect(hours.first?.deltaVsUsual == -60)
    }

    @Test("an hour inside the band is never flagged")
    func insideBand() throws {
        let today = try flatHour(hour: 11, 150) + (try flatHour(hour: 12, 179))
        #expect(PatternAnalysis.outOfBand(today: today, hourly: band(), calendar: utcCalendar).isEmpty)
    }

    @Test("hours with fewer than 5 days behind them are never flagged")
    func thinEvidence() throws {
        let today = try flatHour(hour: 11, 240)
        let thin = band(days: 4)
        #expect(PatternAnalysis.outOfBand(today: today, hourly: thin, calendar: utcCalendar).isEmpty)
        #expect(PatternAnalysis.minDaysForBand == 5)
    }

    @Test("out-of-band hours come back in time order")
    func ordered() throws {
        let today = try flatHour(hour: 20, 230) + (try flatHour(hour: 3, 80)) + (try flatHour(hour: 11, 210))
        let hours = PatternAnalysis.outOfBand(today: today, hourly: band(), calendar: utcCalendar)
        #expect(hours.map(\.hour) == [3, 11, 20])
    }

    @Test("patternHour picks the widest p25–p75, ties to the earliest hour")
    func widestSpread() {
        var hourly = band()
        hourly[8] = HourlyPattern(hour: 8, median: 150, p25: 100, p75: 210, readings: 300, p5: 80, p95: 240, days: 27)
        hourly[19] = HourlyPattern(hour: 19, median: 150, p25: 110, p75: 200, readings: 300, p5: 80, p95: 240, days: 27)

        let widest = PatternAnalysis.patternHour(hourly)
        #expect(widest?.hour == 8)
        #expect(widest?.spread == 110)
        #expect(widest?.days == 27)
    }

    @Test("patternHour ignores hours with thin evidence and returns nil when nothing qualifies")
    func patternHourGate() {
        #expect(PatternAnalysis.patternHour(band(days: 4)) == nil)
        #expect(PatternAnalysis.patternHour(ClinicReportBuilder.hourlyPatterns(from: [], calendar: utcCalendar)) == nil)
    }

    @Test("drill slices ±2 h per day, counts days above the consensus 180 and carries n")
    func drill() throws {
        // Hour 11 across 15–17 June. Day 15 peaks at 200, day 16 at 240, day 17 at 150.
        // Plus a reading 3 h away that must NOT be sliced in.
        var readings: [SensorGlucose] = []
        readings += try flatHour(day: 15, hour: 11, 200, minutes: 4)
        readings += try flatHour(day: 16, hour: 11, 240, minutes: 4)
        readings += try flatHour(day: 17, hour: 11, 150, minutes: 4)
        readings.append(try reading(day: 17, hour: 7, minute: 0, 300))

        let drill = PatternAnalysis.drill(
            hour: 11,
            readings: readings,
            days: 14,
            now: try date(day: 17, hour: 23),
            calendar: utcCalendar
        )

        #expect(drill.hour == 11)
        #expect(drill.traces.count == 3)
        #expect(drill.days == 3)
        #expect(drill.n == 12) // the 07:00 reading is outside 09:30–13:30
        #expect(drill.daysAbove180 == 2)
        #expect(PatternAnalysis.highThresholdMgDL == 180)
        // Newest day last, and only the newest is today.
        #expect(drill.traces.map(\.isToday) == [false, false, true])
        // Offsets are minutes from hour:30 — 11:00 is −30.
        #expect(drill.traces.first?.points.first?.offsetMinutes == -30)
    }

    @Test("drill only looks back `days` days")
    func drillWindow() throws {
        var readings: [SensorGlucose] = []
        readings += try flatHour(day: 15, hour: 11, 200, minutes: 4)
        readings += try flatHour(day: 17, hour: 11, 200, minutes: 4)

        let drill = PatternAnalysis.drill(
            hour: 11,
            readings: readings,
            days: 2,
            now: try date(day: 17, hour: 23),
            calendar: utcCalendar
        )
        // Only 16 + 17 are in the window; 16 has no readings.
        #expect(drill.traces.count == 1)
        #expect(drill.days == 1)
        #expect(drill.n == 4)
    }

    @Test("an empty drill is empty, not a claim")
    func emptyDrill() throws {
        let drill = PatternAnalysis.drill(hour: 2, readings: [], days: 14, now: try date(hour: 12), calendar: utcCalendar)
        #expect(drill.traces.isEmpty)
        #expect(drill.days == 0)
        #expect(drill.n == 0)
        #expect(drill.daysAbove180 == 0)
    }
}

// MARK: - Band geometry

@Suite("Pattern band geometry")
struct PatternBandBuilderTests {
    private func hourly(skipping skipped: Set<Int> = []) -> [HourlyPattern] {
        (0 ..< 24).map { hour in
            skipped.contains(hour)
                ? HourlyPattern(hour: hour, median: nil, p25: nil, p75: nil, readings: 0, p5: nil, p95: nil, days: 0)
                : HourlyPattern(hour: hour, median: 150, p25: 120, p75: 180, readings: 324, p5: 90, p95: 220, days: 27)
        }
    }

    private func build(
        hourly: [HourlyPattern],
        today: [SensorGlucose] = [],
        from: Date,
        to: Date,
        unit: GlucoseUnit = .mgdL
    ) -> PatternBandLayer? {
        PatternBandBuilder.build(
            hourly: hourly,
            today: today,
            domainStart: from,
            domainEnd: to,
            glucoseUnit: unit,
            lookbackDays: 30,
            calendar: utcCalendar
        )
    }

    @Test("the band spans the whole day with edge points at 00:00 and 24:00")
    func edgePoints() throws {
        let layer = try #require(build(hourly: hourly(), from: try date(hour: 6), to: try date(hour: 20)))

        // 24 hour-centre points + both edges.
        #expect(layer.points.count == 26)
        #expect(layer.points.first?.time == (try date(hour: 0)))
        #expect(layer.points.last?.time == (try date(day: 16, hour: 0)))
        // Hour centres sit at hour:30.
        #expect(layer.points[1].time == (try date(hour: 0, minute: 30)))
        #expect(layer.points.map(\.time).sorted() == layer.points.map(\.time))
    }

    @Test("hours with nil quantiles are skipped, edges included")
    func skipsEmptyHours() throws {
        let layer = try #require(build(hourly: hourly(skipping: [0, 5, 23]), from: try date(hour: 6), to: try date(hour: 20)))

        // 21 usable hour centres, and NO edge points (hours 0 and 23 are empty).
        #expect(layer.points.count == 21)
        #expect(layer.points.first?.time == (try date(hour: 1, minute: 30)))
        #expect(layer.points.last?.time == (try date(hour: 22, minute: 30)))
        #expect(layer.points.allSatisfy { $0.p5 <= $0.p25 && $0.p25 <= $0.median && $0.median <= $0.p75 && $0.p75 <= $0.p95 })
    }

    @Test("a band with no usable hour at all is nil, never an empty ghost")
    func noBand() throws {
        #expect(build(hourly: hourly(skipping: Set(0 ..< 24)), from: try date(hour: 6), to: try date(hour: 20)) == nil)
        #expect(build(hourly: [], from: try date(hour: 6), to: try date(hour: 20)) == nil)
    }

    @Test("a domain spanning midnight repeats the band across both days")
    func twoDays() throws {
        let layer = try #require(build(hourly: hourly(), from: try date(day: 15, hour: 18), to: try date(day: 16, hour: 9)))
        #expect(layer.points.first?.time == (try date(day: 15, hour: 0)))
        #expect(layer.points.last?.time == (try date(day: 17, hour: 0)))
        #expect(layer.points.count == 50) // 48 centres + 2 edges
    }

    @Test("mmol/L converts every band value")
    func mmol() throws {
        let layer = try #require(build(hourly: hourly(), from: try date(hour: 6), to: try date(hour: 20), unit: .mmolL))
        let point = try #require(layer.points.first)
        #expect(abs(point.median - 150.toMmolL()) < 0.001)
        #expect(abs(point.p95 - 220.toMmolL()) < 0.001)
        #expect(layer.maxValue.map { abs($0 - 220.toMmolL()) < 0.001 } == true)
    }

    @Test("the pattern hour box lands on the LAST occurrence inside the domain")
    func patternHourSpan() throws {
        var rows = hourly()
        rows[8] = HourlyPattern(hour: 8, median: 150, p25: 100, p75: 220, readings: 324, p5: 80, p95: 240, days: 27)
        let layer = try #require(build(hourly: rows, from: try date(day: 15, hour: 6), to: try date(day: 16, hour: 12)))

        #expect(layer.patternHour?.hour == 8)
        #expect(layer.patternHourSpan?.lowerBound == (try date(day: 16, hour: 8)))
        #expect(layer.patternHourSpan?.upperBound == (try date(day: 16, hour: 9)))
    }

    @Test("out-of-band markers carry their x, today's value and the raw mg/dL delta")
    func outOfBandMarkers() throws {
        let today = try flatHour(hour: 11, 218)
        let layer = try #require(build(hourly: hourly(), today: today, from: try date(hour: 6), to: try date(hour: 20)))

        #expect(layer.outOfBand.count == 1)
        let marker = try #require(layer.outOfBand.first)
        #expect(marker.hour == 11)
        #expect(marker.time == (try date(hour: 11, minute: 30)))
        #expect(marker.deltaMgDL == 68)
        #expect(marker.todayValue == 218)
        #expect(marker.days == 27)
        // The card's copy is built where the display unit is known, so the
        // chart arm renders a string and decides nothing.
        #expect(marker.cardText == "11:00 · +68 VS USUAL · n=27")
        #expect(marker.showsCard)
    }

    @Test("clustered departures keep every tick but only the biggest card")
    func cardSpacing() throws {
        // 01:00 (+6), 02:00 (+7) and 11:00 (+68): the two adjacent small ones
        // would draw two overlapping cards over the trace they describe.
        let today = try flatHour(hour: 1, 187) + (try flatHour(hour: 2, 188)) + (try flatHour(hour: 11, 218))
        let layer = try #require(build(hourly: hourly(), today: today, from: try date(hour: 0), to: try date(hour: 20)))

        #expect(layer.outOfBand.count == 3) // every departure keeps its tick
        #expect(layer.outOfBand.filter(\.showsCard).map(\.hour) == [2, 11]) // +7 beats +6 in its cluster
        #expect(PatternBandBuilder.cardSpacingHours == 6)
    }

    @Test("departures spread across the day each keep their card")
    func cardsWhenSpread() throws {
        let today = try flatHour(hour: 2, 220) + (try flatHour(hour: 11, 218)) + (try flatHour(hour: 20, 90))
        let layer = try #require(build(hourly: hourly(), today: today, from: try date(hour: 0), to: try date(hour: 23)))
        #expect(layer.outOfBand.filter(\.showsCard).map(\.hour) == [2, 11, 20])
    }

    @Test("the layer carries the look-back it was built for")
    func lookback() throws {
        let layer = try #require(build(hourly: hourly(), from: try date(hour: 6), to: try date(hour: 20)))
        #expect(layer.days == 30)
    }
}

// MARK: - Copy

@Suite("Pattern copy")
struct PatternCopyTests {
    @Test("the band chip names the look-back")
    func bandChip() {
        #expect(PatternCopy.bandChip(days: 30) == "▒ YOUR 30-DAY BAND")
        #expect(PatternCopy.bandChip(days: 90) == "▒ YOUR 90-DAY BAND")
    }

    @Test("the out-of-band card is HH:00 · ±delta VS USUAL · n=days")
    func card() {
        #expect(PatternCopy.outOfBandCard(hour: 11, deltaMgDL: 38, days: 27, glucoseUnit: .mgdL) == "11:00 · +38 VS USUAL · n=27")
        #expect(PatternCopy.outOfBandCard(hour: 4, deltaMgDL: -22, days: 9, glucoseUnit: .mgdL) == "04:00 · −22 VS USUAL · n=9")
    }

    @Test("the card converts the delta for mmol/L")
    func cardMmol() {
        // 38 mg/dL ≈ 2.1 mmol/L
        let line = PatternCopy.outOfBandCard(hour: 11, deltaMgDL: 38, days: 27, glucoseUnit: .mmolL)
        #expect(line.hasPrefix("11:00 · +"))
        #expect(line.hasSuffix("VS USUAL · n=27"))
        #expect(line.contains("38") == false)
    }

    @Test("the drill line is k OF N DAYS > 180 HERE · n=readings")
    func drillLine() {
        #expect(PatternCopy.drillLine(daysAbove: 9, days: 14, readings: 612, glucoseUnit: .mgdL) == "9 OF 14 DAYS > 180 HERE · n=612")
    }

    @Test("a drill with too little evidence makes no claim")
    func thinDrill() {
        #expect(PatternCopy.drillLine(daysAbove: 1, days: 3, readings: 40, glucoseUnit: .mgdL) == "n<5 DAYS · KEEP WEARING")
        #expect(PatternCopy.drillLine(daysAbove: 0, days: 0, readings: 0, glucoseUnit: .mgdL) == "n<5 DAYS · KEEP WEARING")
    }

    @Test("the drill line converts the consensus threshold for mmol/L")
    func drillLineMmol() {
        let line = PatternCopy.drillLine(daysAbove: 9, days: 14, readings: 612, glucoseUnit: .mmolL)
        #expect(line.hasPrefix("9 OF 14 DAYS > "))
        #expect(line.hasSuffix("HERE · n=612"))
        #expect(line.contains("180") == false)
    }

    @Test("the hold hint and the held header both name the ±2 h window")
    func hints() {
        #expect(PatternCopy.holdHint(days: 14) == "HOLD AN HOUR → SAME HOUR · 14 D")
        #expect(PatternCopy.heldHint(hour: 11, days: 14) == "11:00 ±2 H · LAST 14 D")
    }

    @Test("the drill never promises more days than the loaded band can reach")
    func drillWindowDays() {
        #expect(PatternCopy.drillWindowDays(lookbackDays: 30) == 14)
        #expect(PatternCopy.drillWindowDays(lookbackDays: 90) == 14)
        #expect(PatternCopy.drillWindowDays(lookbackDays: 7) == 7)
        #expect(PatternCopy.drillWindowDays(lookbackDays: 0) == 1)
        #expect(PatternCopy.holdHint(days: PatternCopy.drillWindowDays(lookbackDays: 7))
            == "HOLD AN HOUR → SAME HOUR · 7 D")
    }

    @Test("no copy in the lab ever tells anyone what to do")
    func noDosingLanguage() {
        let lines = [
            PatternCopy.holdHint(days: 14),
            PatternCopy.heldHint(hour: 7, days: 14),
            PatternCopy.keepWearing,
            PatternCopy.bandChip(days: 30),
            PatternCopy.outOfBandCard(hour: 11, deltaMgDL: 38, days: 27, glucoseUnit: .mgdL),
            PatternCopy.drillLine(daysAbove: 9, days: 14, readings: 612, glucoseUnit: .mgdL),
            PatternCopy.patternHourLabel(days: 27),
        ]
        let banned = ["TAKE", "DOSE", "INJECT", "UNITS", "BOLUS", "CORRECT", "SHOULD", "EAT"]
        for line in lines {
            for word in banned {
                #expect(line.uppercased().contains(word) == false, "\(line) contains \(word)")
            }
        }
    }

    @Test("the pattern hour label carries its n")
    func patternHourLabel() {
        #expect(PatternCopy.patternHourLabel(days: 27) == "PATTERN HOUR · n=27")
    }
}
