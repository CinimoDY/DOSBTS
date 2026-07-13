//
//  ClinicReport.swift
//  DOSBTS
//
//  Pure model + derivations for the clinic-visit report (DMNC-1304). No UI, no
//  Redux, no I/O — the same "pure logic, exhaustively unit-tested" shape as
//  `RatioEstimator` / `IOBCalculator`. The store (ClinicReportStore) fetches raw
//  arrays; `ClinicReportBuilder` turns them into the report's tables.
//
//  The report is deliberately pseudonymous (no name/DOB) and uses the international
//  consensus TIR band (70–180 mg/dL) and hypo threshold (70 mg/dL) — NOT the user's
//  personal alarm profile — so a clinician can compare it against other reports.
//

import Foundation

// MARK: - ClinicReportFormat

enum ClinicReportFormat: Equatable {
    case pdf
    case csv
}

// MARK: - ReportPeriod

/// Selectable report look-back. Raw value = days.
enum ReportPeriod: Int, CaseIterable, Identifiable {
    case twoWeeks = 14
    case oneMonth = 30
    case threeMonths = 90

    var id: Int { rawValue }
    var days: Int { rawValue }
    var label: String { "\(rawValue) DAYS" }
}

// MARK: - HourlyPattern

/// One hour-of-day bucket of the daily glucose pattern. `median`/`p25`/`p75` are `nil`
/// when the hour had no readings across the period; `readings` is that hour's sample count.
struct HourlyPattern: Equatable {
    let hour: Int // 0...23
    let median: Int?
    let p25: Int?
    let p75: Int?
    let readings: Int
}

// MARK: - ClinicReportRaw

/// The raw arrays the store fetches in one read, before assembly. Statistics come from a
/// separate SQL Future (`getSensorGlucoseStatistics`) zipped in by the middleware.
struct ClinicReportRaw {
    let readings: [SensorGlucose]
    let deliveries: [InsulinDelivery]
    let mealCount: Int
    let period: DateInterval
}

// MARK: - ClinicReportData

/// The fully resolved clinic report — pure data, ready to render to PDF or CSV.
struct ClinicReportData {
    let statistics: GlucoseStatistics
    let hourlyPatterns: [HourlyPattern] // always 24 entries, hour 0...23
    let mealCount: Int
    let bolusCounts: [InsulinType: Int]
    let basalCount: Int
    let hypoEpisodeCount: Int
    let period: DateInterval

    /// Total boluses of any type (meal + snack + correction).
    var totalBolusCount: Int { bolusCounts.values.reduce(0, +) }

    /// `getSensorGlucoseStatistics` never fails on an empty DB — it returns degenerate
    /// zeros — so GMI/CV must be suppressed when there's nothing to compute them from.
    var hasSufficientData: Bool { statistics.readings > 0 && statistics.avg > 0 }
}

// MARK: - ClinicReportBuilder

/// Pure derivations for the clinic report. Fully unit-tested without a DB.
enum ClinicReportBuilder {

    // MARK: Thresholds (consensus, not the user's alarm profile)

    /// Consensus hypo threshold (mg/dL) for the episode count.
    static let hypoThresholdMgDL: Int = 70
    /// A hypo episode must span at least this long to count (min).
    static let hypoMinDurationMinutes: Int = 15
    /// Two low stretches this far apart (min) count as separate episodes.
    static let hypoSeparationMinutes: Int = 30

    // MARK: Assembly

    /// Combine the separately-fetched statistics with the raw arrays into the final report.
    static func assemble(statistics: GlucoseStatistics, raw: ClinicReportRaw) -> ClinicReportData {
        let bolusCounts = Dictionary(
            grouping: raw.deliveries.filter { $0.type != .basal },
            by: { $0.type }
        ).mapValues { $0.count }
        let basalCount = raw.deliveries.filter { $0.type == .basal }.count

        return ClinicReportData(
            statistics: statistics,
            hourlyPatterns: hourlyPatterns(from: raw.readings),
            mealCount: raw.mealCount,
            bolusCounts: bolusCounts,
            basalCount: basalCount,
            hypoEpisodeCount: hypoEpisodes(from: raw.readings),
            period: raw.period
        )
    }

    // MARK: Hourly pattern

    /// 24 hour-of-day buckets (median + P25/P75) from the period's readings. ALWAYS returns
    /// 24 entries (hour 0...23); empty hours get `nil` quantiles and 0 readings.
    static func hourlyPatterns(from readings: [SensorGlucose], calendar: Calendar = .current) -> [HourlyPattern] {
        var buckets: [Int: [Int]] = [:]
        for reading in readings {
            let hour = calendar.component(.hour, from: reading.timestamp)
            buckets[hour, default: []].append(reading.glucoseValue)
        }
        return (0 ..< 24).map { hour in
            let values = (buckets[hour] ?? []).sorted()
            guard !values.isEmpty else {
                return HourlyPattern(hour: hour, median: nil, p25: nil, p75: nil, readings: 0)
            }
            return HourlyPattern(
                hour: hour,
                median: percentile(values, 0.5),
                p25: percentile(values, 0.25),
                p75: percentile(values, 0.75),
                readings: values.count
            )
        }
    }

    // MARK: Hypo episodes

    /// Count of hypo episodes: maximal runs of low readings (< `hypoThresholdMgDL`) spanning
    /// ≥ `hypoMinDurationMinutes`; consecutive lows more than `hypoSeparationMinutes` apart start
    /// a new episode (a return to range shorter than that does not split one).
    static func hypoEpisodes(from readings: [SensorGlucose]) -> Int {
        let lows = readings
            .filter { $0.glucoseValue < hypoThresholdMgDL }
            .map { $0.timestamp }
            .sorted()
        guard let firstLow = lows.first else { return 0 }

        var episodes = 0
        var episodeStart = firstLow
        var previousLow = firstLow
        let minDuration = Double(hypoMinDurationMinutes * 60)
        let separation = Double(hypoSeparationMinutes * 60)

        func closeEpisode(end: Date) {
            if end.timeIntervalSince(episodeStart) >= minDuration { episodes += 1 }
        }

        for low in lows.dropFirst() {
            if low.timeIntervalSince(previousLow) >= separation {
                closeEpisode(end: previousLow)
                episodeStart = low
            }
            previousLow = low
        }
        closeEpisode(end: previousLow)
        return episodes
    }

    // MARK: Statistics helper

    /// Linear-interpolation percentile (type-7 / numpy default), rounded to an Int glucose
    /// value. `sortedValues` must be sorted ascending; empty → 0 (callers gate on emptiness).
    static func percentile(_ sortedValues: [Int], _ p: Double) -> Int {
        guard let first = sortedValues.first else { return 0 }
        if sortedValues.count == 1 { return first }
        let rank = p * Double(sortedValues.count - 1)
        let lower = Int(rank.rounded(.down))
        let upper = Int(rank.rounded(.up))
        if lower == upper { return sortedValues[lower] }
        let fraction = rank - Double(lower)
        let interpolated = Double(sortedValues[lower]) + fraction * Double(sortedValues[upper] - sortedValues[lower])
        return Int(interpolated.rounded())
    }
}
