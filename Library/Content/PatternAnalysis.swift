//
//  PatternAnalysis.swift
//  DOSBTS
//
//  Chart Lab P4 (DMNC-1503) — pure pattern derivations for `LAB: PATTERNS`.
//  No SwiftUI, no store, no database: everything here is a function of the
//  hourly band (`ClinicReportBuilder.hourlyPatterns`) and raw readings, so the
//  claims the tab makes on screen are the claims these tests pin.
//
//  Three discipline rules run through the whole file:
//
//  1. Every number ships with its `n`. An hour with four days behind it is not
//     a pattern, so nothing is flagged below `minDaysForBand`.
//  2. The high threshold is the **consensus 180 mg/dL**, not the user's alarm
//     profile — the same discipline the clinic report keeps (CLAUDE.md), and
//     the drill line says `> 180` out loud so the number is never mistaken for
//     a personal target.
//  3. Nothing here is dosing advice. `PatternCopy` is the only place the tab's
//     sentences are written, so "never prescribes" is a property of one file.
//

import Foundation

// MARK: - OutOfBandHour

/// An hour where today's median sits outside the user's own usual p25–p75.
/// All glucose values are **mg/dL** (the storage unit) — conversion happens at
/// the edge, in `PatternBandBuilder` / `PatternCopy`.
struct OutOfBandHour: Equatable {
    let hour: Int
    /// Start of the actual hour occurrence in the chart's window, so the mark
    /// can be placed on a domain that may span two calendar days.
    let hourStart: Date
    let todayMedian: Int
    let usualMedian: Int
    /// Signed: today minus usual.
    let deltaVsUsual: Int
    /// Distinct days behind the usual figure.
    let days: Int
}

// MARK: - PatternHour

/// The hour of the day this person is least predictable in — the widest
/// p25–p75 spread. It is a question ("what happens here?"), never an answer.
struct PatternHour: Equatable {
    let hour: Int
    let spread: Int
    let days: Int
}

// MARK: - SameHourDrill

/// One reading in a drill trace, positioned relative to the hour's centre.
struct SameHourPoint: Equatable {
    /// Minutes from `hour:30` of that day — negative before, positive after.
    let offsetMinutes: Double
    /// mg/dL.
    let value: Int
}

/// One day's slice of the same hour, oldest day first.
struct SameHourTrace: Equatable, Identifiable {
    let day: Date
    let isToday: Bool
    let points: [SameHourPoint]

    var id: Date { day }
    var peak: Int? { points.map(\.value).max() }
}

/// The same hour ±2 h across the last N days.
struct SameHourDrill: Equatable {
    let hour: Int
    let traces: [SameHourTrace]
    /// Days whose slice peaked above the consensus 180 mg/dL.
    let daysAbove180: Int
    /// Days with any reading in the window (`traces.count`).
    let days: Int
    /// Readings in the window.
    let n: Int
}

// MARK: - PatternAnalysis

enum PatternAnalysis {
    /// Below this many distinct days, an hour is a coincidence, not a pattern.
    static let minDaysForBand = 5
    /// The drill's fixed look-back — short enough that "the same hour" still
    /// means the same routine.
    static let drillDays = 14
    /// ±2 h around the hour's centre.
    static let drillHalfWidthMinutes = 120
    /// Consensus high threshold (mg/dL) — deliberately NOT the user's alarm
    /// profile, so the drill line means the same thing on every phone.
    static let highThresholdMgDL = 180

    // P-later: split by DayCohort — once P2's regimes label each day, the same
    // band can be computed per cohort (workday / rest day / high-activity) and
    // the out-of-band test run against the matching cohort instead of the
    // pooled one. The seam is `hourly:` — pass a cohort-filtered band in.

    /// Hours where today's median leaves the user's own p25–p75. Time-ordered.
    ///
    /// `today` is whatever the chart is plotting (a picked day, or the rolling
    /// window), so hours are bucketed by their ACTUAL occurrence — a window
    /// that spans midnight still flags the right one.
    static func outOfBand(
        today: [SensorGlucose],
        hourly: [HourlyPattern],
        calendar: Calendar = .current
    ) -> [OutOfBandHour] {
        guard !today.isEmpty, !hourly.isEmpty else { return [] }

        var buckets: [Date: [Int]] = [:]
        for reading in today {
            let start = startOfHour(reading.timestamp, calendar: calendar)
            buckets[start, default: []].append(reading.glucoseValue)
        }

        return buckets.keys.sorted().compactMap { hourStart -> OutOfBandHour? in
            let hour = calendar.component(.hour, from: hourStart)
            guard let usual = hourly.first(where: { $0.hour == hour }),
                  usual.days >= minDaysForBand,
                  let p25 = usual.p25,
                  let p75 = usual.p75,
                  let usualMedian = usual.median,
                  let values = buckets[hourStart]
            else { return nil }

            let todayMedian = ClinicReportBuilder.percentile(values.sorted(), 0.5)
            guard todayMedian > p75 || todayMedian < p25 else { return nil }

            return OutOfBandHour(
                hour: hour,
                hourStart: hourStart,
                todayMedian: todayMedian,
                usualMedian: usualMedian,
                deltaVsUsual: todayMedian - usualMedian,
                days: usual.days
            )
        }
    }

    /// The widest p25–p75 among hours with enough days behind them. Ties go to
    /// the earliest hour, so the answer is stable between renders.
    static func patternHour(_ hourly: [HourlyPattern]) -> PatternHour? {
        hourly
            .compactMap { row -> PatternHour? in
                guard row.days >= minDaysForBand, let p25 = row.p25, let p75 = row.p75 else { return nil }
                return PatternHour(hour: row.hour, spread: p75 - p25, days: row.days)
            }
            .max { left, right in
                left.spread == right.spread ? left.hour > right.hour : left.spread < right.spread
            }
    }

    /// The same hour ±2 h on each of the last `days` days (today included).
    /// Days with no readings in the window are dropped — an absent day is not a
    /// day "below 180".
    static func drill(
        hour: Int,
        readings: [SensorGlucose],
        days: Int = drillDays,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SameHourDrill {
        let halfWidth = TimeInterval(drillHalfWidthMinutes * 60)
        let today = calendar.startOfDay(for: now)
        let sorted = readings.sorted { $0.timestamp < $1.timestamp }

        var traces: [SameHourTrace] = []
        for back in stride(from: max(days, 1) - 1, through: 0, by: -1) {
            guard let dayStart = calendar.date(byAdding: .day, value: -back, to: today),
                  let centre = calendar.date(byAdding: .minute, value: hour * 60 + 30, to: dayStart)
            else { continue }

            let window = centre.addingTimeInterval(-halfWidth) ... centre.addingTimeInterval(halfWidth)
            let points = sorted
                .filter { window.contains($0.timestamp) }
                .map {
                    SameHourPoint(
                        offsetMinutes: $0.timestamp.timeIntervalSince(centre) / 60,
                        value: $0.glucoseValue
                    )
                }
            guard !points.isEmpty else { continue }

            traces.append(SameHourTrace(day: dayStart, isToday: dayStart == today, points: points))
        }

        return SameHourDrill(
            hour: hour,
            traces: traces,
            daysAbove180: traces.filter { ($0.peak ?? 0) > highThresholdMgDL }.count,
            days: traces.count,
            n: traces.reduce(0) { $0 + $1.points.count }
        )
    }

    /// Start of the hour a timestamp falls in (calendar-aware, so it survives a
    /// DST transition that a `floor(t / 3600)` would slide by an hour).
    static func startOfHour(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour], from: date)) ?? date
    }
}

// MARK: - PatternBandPoint

/// One sample of the ghost band, in the user's DISPLAY unit (the chart's marks
/// plot display units — see the P0 errata on double conversion).
struct PatternBandPoint: Equatable {
    let time: Date
    let median: Double
    let p25: Double
    let p75: Double
    let p5: Double
    let p95: Double
}

// MARK: - OutOfBandMarker

/// An out-of-band hour, positioned and converted for the chart.
struct OutOfBandMarker: Equatable, Identifiable {
    /// The hour's centre (`hour:30`) — where the tick and the card hang.
    let time: Date
    let hour: Int
    /// RAW mg/dL, so the copy can convert it exactly once.
    let deltaMgDL: Int
    /// Today's median for that hour, in display units — the card's anchor, so
    /// it always sits on the trace it is talking about.
    let todayValue: Double
    let days: Int
    /// Rendered here rather than in the chart arm: the builder is the one place
    /// that knows the display unit, and `LabOverlayMarks.marks(for:series:yMax:)`
    /// is a shared P0 signature that must stay as it is for the sibling arms.
    let cardText: String
    /// Whether this marker gets the full card, or only its axis tick. A chart
    /// annotation is about six hours wide at the 24 h zoom, so four flagged
    /// hours would draw four overlapping cards over the trace they describe
    /// (observed on-simulator). Every departure keeps its tick; the card goes
    /// to the biggest ones that can be read (see `cardSpacingHours`).
    let showsCard: Bool

    var id: Date { time }
}

// MARK: - PatternBandLayer

/// Everything the `.ghostBand` overlay arm draws. Pure geometry: the arm turns
/// it into marks and decides nothing.
struct PatternBandLayer: Equatable {
    let points: [PatternBandPoint]
    let patternHour: PatternHour?
    /// The pattern hour's span inside the chart's own domain, or nil when that
    /// hour does not occur in the visible days.
    let patternHourSpan: ClosedRange<Date>?
    let outOfBand: [OutOfBandMarker]
    /// The look-back the band was built from, for the unit-row chip.
    let days: Int

    /// The top of the band, in display units — fed into the chart's y floor so
    /// a p95 above today's maximum widens the scale instead of being clipped.
    var maxValue: Double? { points.map(\.p95).max() }
}

// MARK: - PatternBandInput

/// The render-stable slice of `LabPatternEvidence` the chart snapshot carries:
/// 24 hourly rows and the look-back label, never the raw readings.
struct PatternBandInput: Equatable {
    let hourly: [HourlyPattern]
    let days: Int
}

// MARK: - PatternBandBuilder

enum PatternBandBuilder {
    /// Minimum separation between two out-of-band CARDS, in hours. Roughly the
    /// width of one card at the widest zoom, so cards never overlap each other.
    static let cardSpacingHours = 6

    /// Build the band across every calendar day the chart's domain touches.
    ///
    /// The band is the same 24-hour shape on each day, so a domain that spans
    /// midnight (the rolling window) gets it twice rather than a curve that
    /// stops at the day boundary. Returns nil when no hour has data at all —
    /// an empty ghost is worse than none.
    static func build(
        hourly: [HourlyPattern],
        today: [SensorGlucose],
        domainStart: Date,
        domainEnd: Date,
        glucoseUnit: GlucoseUnit,
        lookbackDays: Int,
        calendar: Calendar = .current
    ) -> PatternBandLayer? {
        guard domainStart <= domainEnd else { return nil }
        let usable = hourly.filter { $0.median != nil && $0.p25 != nil && $0.p75 != nil }
        guard !usable.isEmpty else { return nil }

        let byHour = Dictionary(uniqueKeysWithValues: hourly.map { ($0.hour, $0) })
        let firstDay = calendar.startOfDay(for: domainStart)
        let lastDay = calendar.startOfDay(for: domainEnd)

        var days: [Date] = []
        var cursor = firstDay
        while cursor <= lastDay, days.count < 400 {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        guard let spanStart = days.first,
              let spanEndDay = days.last,
              let spanEnd = calendar.date(byAdding: .day, value: 1, to: spanEndDay)
        else { return nil }

        var points: [PatternBandPoint] = []

        // Leading edge: hour 0's shape carried back to 00:00, so the band meets
        // the plot's left edge instead of starting half an hour in.
        if let first = byHour[0], let point = bandPoint(first, at: spanStart, unit: glucoseUnit) {
            points.append(point)
        }

        for day in days {
            for hour in 0 ..< 24 {
                guard let row = byHour[hour],
                      let centre = calendar.date(byAdding: .minute, value: hour * 60 + 30, to: day),
                      let point = bandPoint(row, at: centre, unit: glucoseUnit)
                else { continue }
                points.append(point)
            }
        }

        // Trailing edge: hour 23's shape carried forward to the next midnight.
        if let last = byHour[23], let point = bandPoint(last, at: spanEnd, unit: glucoseUnit) {
            points.append(point)
        }

        guard !points.isEmpty else { return nil }

        let widest = PatternAnalysis.patternHour(hourly)
        let span = widest.flatMap { hour in
            patternHourSpan(hour: hour.hour, days: days, domainStart: domainStart, domainEnd: domainEnd, calendar: calendar)
        }

        let hits = PatternAnalysis.outOfBand(today: today, hourly: hourly, calendar: calendar)
        let carded = cardedTimes(hits, calendar: calendar)
        let markers = hits.compactMap { hit -> OutOfBandMarker? in
            guard let centre = calendar.date(byAdding: .minute, value: 30, to: hit.hourStart) else { return nil }
            return OutOfBandMarker(
                time: centre,
                hour: hit.hour,
                deltaMgDL: hit.deltaVsUsual,
                todayValue: display(hit.todayMedian, unit: glucoseUnit),
                days: hit.days,
                cardText: PatternCopy.outOfBandCard(
                    hour: hit.hour,
                    deltaMgDL: hit.deltaVsUsual,
                    days: hit.days,
                    glucoseUnit: glucoseUnit
                ),
                showsCard: carded.contains(hit.hourStart)
            )
        }

        return PatternBandLayer(
            points: points,
            patternHour: widest,
            patternHourSpan: span,
            outOfBand: markers,
            days: lookbackDays
        )
    }

    // MARK: Private

    /// Biggest departure first, then anything at least `cardSpacingHours` from
    /// an already-carded one. Deterministic (ties break on the earlier hour), so
    /// the same day never renders two different sets of cards.
    private static func cardedTimes(_ hits: [OutOfBandHour], calendar: Calendar) -> Set<Date> {
        var kept: [Date] = []
        let spacing = TimeInterval(cardSpacingHours * 3600)

        for hit in hits.sorted(by: {
            abs($0.deltaVsUsual) == abs($1.deltaVsUsual)
                ? $0.hourStart < $1.hourStart
                : abs($0.deltaVsUsual) > abs($1.deltaVsUsual)
        }) {
            let clashes = kept.contains { abs($0.timeIntervalSince(hit.hourStart)) < spacing }
            if !clashes { kept.append(hit.hourStart) }
        }
        return Set(kept)
    }

    private static func bandPoint(_ row: HourlyPattern, at time: Date, unit: GlucoseUnit) -> PatternBandPoint? {
        guard let median = row.median, let p25 = row.p25, let p75 = row.p75 else { return nil }
        // p5/p95 are additive: a band built before they existed (or an hour
        // with a single reading) falls back to the quartiles rather than
        // drawing a wash of nothing.
        return PatternBandPoint(
            time: time,
            median: display(median, unit: unit),
            p25: display(p25, unit: unit),
            p75: display(p75, unit: unit),
            p5: display(row.p5 ?? p25, unit: unit),
            p95: display(row.p95 ?? p75, unit: unit)
        )
    }

    /// The LAST occurrence of the hour inside the domain — on a rolling window
    /// that covers the same hour twice, the box belongs on today's.
    private static func patternHourSpan(
        hour: Int,
        days: [Date],
        domainStart: Date,
        domainEnd: Date,
        calendar: Calendar
    ) -> ClosedRange<Date>? {
        var found: ClosedRange<Date>?
        for day in days {
            guard let start = calendar.date(byAdding: .minute, value: hour * 60, to: day),
                  let end = calendar.date(byAdding: .hour, value: 1, to: start)
            else { continue }
            guard end > domainStart, start < domainEnd else { continue }
            found = start ... end
        }
        return found
    }

    private static func display(_ mgdl: Int, unit: GlucoseUnit) -> Double {
        unit == .mmolL ? mgdl.toMmolL() : mgdl.toDouble()
    }
}

// MARK: - PatternCopy

/// Every sentence `LAB: PATTERNS` puts on screen, in one pure place — so the
/// "carries its n, never prescribes" rule is a property a test can check.
enum PatternCopy {
    static let keepWearing = "n<\(PatternAnalysis.minDaysForBand) DAYS · KEEP WEARING"

    /// The drill can only reach as far back as the loaded evidence: with the 7d
    /// chip selected there are seven days in hand, and promising "14 D" would be
    /// a claim the data cannot honour (caught on-simulator).
    static func drillWindowDays(lookbackDays: Int) -> Int {
        min(PatternAnalysis.drillDays, max(lookbackDays, 1))
    }

    static func holdHint(days: Int) -> String {
        "HOLD AN HOUR → SAME HOUR · \(days) D"
    }

    static func bandChip(days: Int) -> String {
        "▒ YOUR \(days)-DAY BAND"
    }

    static func heldHint(hour: Int, days: Int) -> String {
        "\(hourLabel(hour)) ±\(PatternAnalysis.drillHalfWidthMinutes / 60) H · LAST \(days) D"
    }

    static func patternHourLabel(days: Int) -> String {
        "PATTERN HOUR · n=\(days)"
    }

    /// `11:00 · +38 VS USUAL · n=27`. The delta is raw mg/dL and is converted
    /// here exactly once (`Int.asGlucose` converts AND formats — correct for a
    /// storage-unit value, wrong for one a datapoint builder already converted).
    static func outOfBandCard(hour: Int, deltaMgDL: Int, days: Int, glucoseUnit: GlucoseUnit) -> String {
        let sign = deltaMgDL < 0 ? "−" : "+"
        let magnitude = abs(deltaMgDL).asGlucose(glucoseUnit: glucoseUnit)
        return "\(hourLabel(hour)) · \(sign)\(magnitude) VS USUAL · n=\(days)"
    }

    /// `9 OF 14 DAYS > 180 HERE · n=612`, or an honest refusal to claim.
    static func drillLine(daysAbove: Int, days: Int, readings: Int, glucoseUnit: GlucoseUnit) -> String {
        guard days >= PatternAnalysis.minDaysForBand else { return keepWearing }
        let threshold = PatternAnalysis.highThresholdMgDL.asGlucose(glucoseUnit: glucoseUnit)
        return "\(daysAbove) OF \(days) DAYS > \(threshold) HERE · n=\(readings)"
    }

    /// Locale-independent 24-hour label — the lab is an instrument panel, not a
    /// clock face, and `04:00` must never become `4 AM` in the middle of a
    /// fixed-width line.
    static func hourLabel(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }
}
