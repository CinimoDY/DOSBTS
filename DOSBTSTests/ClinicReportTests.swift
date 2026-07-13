//
//  ClinicReportTests.swift
//  DOSBTSTests
//
//  Pins the pure clinic-report derivations (DMNC-1304): hourly bucketing, percentile math,
//  hypo-episode run-splitting, and event counting.
//

import Foundation
import Testing
@testable import DOSBTSApp

// MARK: - Fixtures

private var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    return calendar
}

private func date(hour: Int, minute: Int = 0) throws -> Date {
    try #require(utcCalendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: hour, minute: minute)))
}

private func low(hour: Int, minute: Int) throws -> SensorGlucose {
    SensorGlucose(timestamp: try date(hour: hour, minute: minute), rawGlucoseValue: 60, intGlucoseValue: 60)
}

private func emptyStats() -> GlucoseStatistics {
    GlucoseStatistics(readings: 0, fromTimestamp: Date(), toTimestamp: Date(), gmi: 0, avg: 0, tbr: 0, tar: 0, variance: 0, days: 0, maxDays: 0)
}

// MARK: - Render seam (ImageRenderer→PDF + CSV file generation)

/// Integration coverage for the file-generation seam the pure-builder tests don't reach:
/// `ClinicReportFile.renderPDF` (MainActor `ImageRenderer` → CGContext PDF) and `writeCSV`.
/// This is the codebase's first PDF path, so it's worth pinning that it produces bytes.
@Suite("ClinicReport — render seam")
@MainActor
struct ClinicReportRenderSeamTests {
    @Test("renderPDF writes a valid non-empty PDF; writeCSV writes a populated CSV")
    func renderSeam() throws {
        let calendar = utcCalendar
        var readings: [SensorGlucose] = []
        for hour in 0 ..< 24 {
            for minute in stride(from: 0, to: 60, by: 15) {
                let timestamp = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: hour, minute: minute)))
                let value = 110 + (hour % 6) * 12
                readings.append(SensorGlucose(timestamp: timestamp, rawGlucoseValue: value, intGlucoseValue: value))
            }
        }
        let deliveries = [
            InsulinDelivery(starts: Date(), ends: Date(), units: 5, type: .mealBolus),
            InsulinDelivery(starts: Date(), ends: Date(), units: 2, type: .snackBolus),
            InsulinDelivery(starts: Date(), ends: Date(), units: 3, type: .correctionBolus),
            InsulinDelivery(starts: Date(), ends: Date(), units: 20, type: .basal),
        ]
        let statistics = GlucoseStatistics(readings: readings.count, fromTimestamp: Date(), toTimestamp: Date(), gmi: 6.4, avg: 134, tbr: 3, tar: 22, variance: 1024, days: 30, maxDays: 30)
        let raw = ClinicReportRaw(readings: readings, deliveries: deliveries, mealCount: 14, period: DateInterval(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 1)))
        let data = ClinicReportBuilder.assemble(statistics: statistics, raw: raw)

        let pdfURL = try #require(ClinicReportFile.renderPDF(data: data, glucoseUnit: .mgdL, appBuild: "999"))
        let pdfData = try Data(contentsOf: pdfURL)
        #expect(pdfData.count > 1000)
        #expect(pdfData.prefix(4) == Data("%PDF".utf8))

        let csvURL = try #require(ClinicReportFile.writeCSV(data: data, glucoseUnit: .mgdL))
        let csvString = try String(contentsOf: csvURL, encoding: .utf8)
        #expect(csvString.contains("DOSBTS CLINIC REPORT"))
        #expect(csvString.contains("HOURLY PATTERN"))
        #expect(csvString.contains("EVENTS"))
    }
}

// MARK: - Hourly pattern

@Suite("ClinicReportBuilder — hourly pattern")
struct ClinicReportHourlyTests {

    @Test("Always 24 entries (hour 0...23), empty when no readings")
    func always24() {
        let patterns = ClinicReportBuilder.hourlyPatterns(from: [])
        #expect(patterns.count == 24)
        #expect(patterns.map(\.hour) == Array(0 ..< 24))
        #expect(patterns.allSatisfy { $0.readings == 0 && $0.median == nil && $0.p25 == nil && $0.p75 == nil })
    }

    @Test("Readings at 23:59 and 00:01 land in different hour buckets")
    func bucketBoundary() throws {
        let r1 = SensorGlucose(timestamp: try date(hour: 23, minute: 59), rawGlucoseValue: 100, intGlucoseValue: 100)
        let r2 = SensorGlucose(timestamp: try date(hour: 0, minute: 1), rawGlucoseValue: 120, intGlucoseValue: 120)
        let patterns = ClinicReportBuilder.hourlyPatterns(from: [r1, r2], calendar: utcCalendar)
        #expect(patterns[23].readings == 1)
        #expect(patterns[23].median == 100)
        #expect(patterns[0].readings == 1)
        #expect(patterns[0].median == 120)
        // Every other hour is empty.
        #expect(patterns.filter { $0.readings > 0 }.count == 2)
    }
}

// MARK: - Percentile

@Suite("ClinicReportBuilder — percentile")
struct ClinicReportPercentileTests {

    @Test("Odd count: median + quartiles (type-7)")
    func odd() {
        let values = [100, 110, 120, 130, 140]
        #expect(ClinicReportBuilder.percentile(values, 0.5) == 120)
        #expect(ClinicReportBuilder.percentile(values, 0.25) == 110)
        #expect(ClinicReportBuilder.percentile(values, 0.75) == 130)
    }

    @Test("Even count: median interpolates and rounds")
    func even() {
        #expect(ClinicReportBuilder.percentile([100, 110, 120, 130], 0.5) == 115)
    }

    @Test("Single value returns itself; empty returns 0")
    func degenerate() {
        #expect(ClinicReportBuilder.percentile([137], 0.5) == 137)
        #expect(ClinicReportBuilder.percentile([], 0.5) == 0)
    }
}

// MARK: - Hypo episodes

@Suite("ClinicReportBuilder — hypo episodes")
struct ClinicReportHypoTests {

    @Test("A 10-minute dip is too short to count")
    func shortDip() throws {
        let readings = try [0, 5, 10].map { try low(hour: 3, minute: $0) } // span 10 min < 15
        #expect(ClinicReportBuilder.hypoEpisodes(from: readings) == 0)
    }

    @Test("A 20-minute dip counts as one episode")
    func oneEpisode() throws {
        let readings = try [0, 5, 10, 15, 20].map { try low(hour: 3, minute: $0) } // span 20 min
        #expect(ClinicReportBuilder.hypoEpisodes(from: readings) == 1)
    }

    @Test("Two dips separated by 40 min in range count as two episodes")
    func twoEpisodes() throws {
        let dip1 = try [0, 5, 10, 15, 20].map { try low(hour: 3, minute: $0) } // 3:00–3:20
        let dip2 = try [0, 5, 10, 15, 20].map { try low(hour: 4, minute: $0) } // 4:00–4:20 (40 min later)
        #expect(ClinicReportBuilder.hypoEpisodes(from: dip1 + dip2) == 2)
    }

    @Test("Two lows only 10 min apart merge into one episode")
    func mergedEpisode() throws {
        let part1 = try [0, 5, 10].map { try low(hour: 3, minute: $0) }
        let part2 = try [20, 25, 30].map { try low(hour: 3, minute: $0) } // 10-min in-range gap < 30
        #expect(ClinicReportBuilder.hypoEpisodes(from: part1 + part2) == 1) // merged span 30 min
    }

    @Test("No lows → zero episodes")
    func noLows() throws {
        let normal = SensorGlucose(timestamp: try date(hour: 3), rawGlucoseValue: 120, intGlucoseValue: 120)
        #expect(ClinicReportBuilder.hypoEpisodes(from: [normal]) == 0)
    }
}

// MARK: - Assembly / event counting

@Suite("ClinicReportBuilder — assembly")
struct ClinicReportAssemblyTests {

    private func raw(deliveries: [InsulinDelivery], mealCount: Int, readings: [SensorGlucose] = []) -> ClinicReportRaw {
        ClinicReportRaw(
            readings: readings,
            deliveries: deliveries,
            mealCount: mealCount,
            period: DateInterval(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 1000))
        )
    }

    @Test("Boluses counted by type; basal excluded from bolusCounts")
    func eventCounts() {
        let deliveries = [
            InsulinDelivery(starts: Date(), ends: Date(), units: 5, type: .mealBolus),
            InsulinDelivery(starts: Date(), ends: Date(), units: 2, type: .mealBolus),
            InsulinDelivery(starts: Date(), ends: Date(), units: 1, type: .snackBolus),
            InsulinDelivery(starts: Date(), ends: Date(), units: 3, type: .correctionBolus),
            InsulinDelivery(starts: Date(), ends: Date(), units: 20, type: .basal),
        ]
        let data = ClinicReportBuilder.assemble(statistics: emptyStats(), raw: raw(deliveries: deliveries, mealCount: 7))
        #expect(data.bolusCounts[.mealBolus] == 2)
        #expect(data.bolusCounts[.snackBolus] == 1)
        #expect(data.bolusCounts[.correctionBolus] == 1)
        #expect(data.bolusCounts[.basal] == nil)
        #expect(data.basalCount == 1)
        #expect(data.totalBolusCount == 4)
        #expect(data.mealCount == 7)
        #expect(data.hourlyPatterns.count == 24)
    }

    @Test("hasSufficientData is false with zero readings (fresh install stays valid)")
    func insufficientData() {
        let data = ClinicReportBuilder.assemble(statistics: emptyStats(), raw: raw(deliveries: [], mealCount: 0))
        #expect(data.hasSufficientData == false)
        #expect(data.hypoEpisodeCount == 0)
        #expect(data.hourlyPatterns.count == 24)
    }
}
