//
//  ChartLabFactsTests.swift
//  DOSBTSTests
//
//  Chart Lab P5 (DMNC-1505 / DMNC-1500): the cited-facts engine. The hypo
//  episode INTERVALS behind the Black Box card, the `LabFigure` / `LabCaption`
//  contract (a number the lab may show cannot exist without its `n`), the
//  `ChartHighlights` detectors and ranking, and the source-scan that keeps
//  dosing language out of every string the lab prints.
//
//  Everything here is pure — no view instantiation, no GRDB, no network.
//

import Foundation
import Testing
@testable import DOSBTSApp

// MARK: - Shared helpers

// Copies of the file-private helpers in DirectReducerTests.swift (they are
// file-private there, so every test file carries its own pair).
private func makeState() -> AppState {
    AppState(defaults: makeTestDefaults())
}

/// Exact minute boundary (1_757_664_000 / 60 == 29_294_400), so the models'
/// `toRounded(on: 1, .minute)` never shifts a fixture.
private let base = Date(timeIntervalSince1970: 1_757_664_000)

private func at(_ minutes: Int) -> Date {
    base.addingTimeInterval(TimeInterval(minutes * 60))
}

private func reading(_ minutes: Int, _ value: Int) -> SensorGlucose {
    SensorGlucose(timestamp: at(minutes), rawGlucoseValue: value, intGlucoseValue: value)
}

/// A run of readings every 5 minutes, inclusive of both ends.
private func run(from: Int, to: Int, value: Int) -> [SensorGlucose] {
    stride(from: from, through: to, by: 5).map { reading($0, value) }
}

// MARK: - Hypo episode intervals

@Suite("Hypo episode intervals")
struct HypoEpisodeIntervalTests {
    @Test("one 50-minute run is one interval with the run's own bounds")
    func singleRun() {
        let readings = run(from: 0, to: 50, value: 62)
        let intervals = ClinicReportBuilder.hypoEpisodeIntervals(from: readings)

        #expect(intervals.count == 1)
        #expect(intervals.first?.start == at(0))
        #expect(intervals.first?.end == at(50))
    }

    @Test("two runs 40 minutes apart are two intervals")
    func twoRuns() {
        let readings = run(from: 0, to: 20, value: 62) + run(from: 60, to: 80, value: 60)
        let intervals = ClinicReportBuilder.hypoEpisodeIntervals(from: readings)

        #expect(intervals.count == 2)
        #expect(intervals.first?.start == at(0))
        #expect(intervals.first?.end == at(20))
        #expect(intervals.last?.start == at(60))
        #expect(intervals.last?.end == at(80))
    }

    @Test("a 10-minute dip is too short to be an episode")
    func shortDip() {
        let intervals = ClinicReportBuilder.hypoEpisodeIntervals(from: run(from: 0, to: 10, value: 65))
        #expect(intervals.isEmpty)
    }

    @Test("a return to range shorter than the separation does not split an episode")
    func shortRecoveryDoesNotSplit() {
        // Lows at 0–20 and 40–60: the 20-minute in-range stretch is under the
        // 30-minute separation, so it is ONE 60-minute episode.
        let readings = run(from: 0, to: 20, value: 62)
            + run(from: 25, to: 35, value: 120)
            + run(from: 40, to: 60, value: 64)
        let intervals = ClinicReportBuilder.hypoEpisodeIntervals(from: readings)

        #expect(intervals.count == 1)
        #expect(intervals.first?.start == at(0))
        #expect(intervals.first?.end == at(60))
    }

    @Test("nothing low at all is no intervals")
    func noLows() {
        #expect(ClinicReportBuilder.hypoEpisodeIntervals(from: run(from: 0, to: 120, value: 110)).isEmpty)
    }

    @Test("the legacy count is exactly the interval count — on the same fixture")
    func countMatchesLegacy() {
        let fixture = run(from: 0, to: 50, value: 62)
            + run(from: 120, to: 140, value: 55)
            + run(from: 200, to: 210, value: 60) // too short — counted by neither
            + run(from: 300, to: 400, value: 140)

        #expect(
            ClinicReportBuilder.hypoEpisodes(from: fixture)
                == ClinicReportBuilder.hypoEpisodeIntervals(from: fixture).count
        )
        #expect(ClinicReportBuilder.hypoEpisodes(from: fixture) == 2)
    }

    @Test("unsorted input is still walked in time order")
    func unsortedInput() {
        let intervals = ClinicReportBuilder.hypoEpisodeIntervals(from: run(from: 0, to: 50, value: 62).reversed())
        #expect(intervals.count == 1)
        #expect(intervals.first?.start == at(0))
        #expect(intervals.first?.end == at(50))
    }
}
