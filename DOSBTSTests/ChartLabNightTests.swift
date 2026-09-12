//
//  ChartLabNightTests.swift
//  DOSBTSTests
//
//  Chart Lab P1 (DMNC-1506 / DMNC-1500): the whole-system window loader and
//  `LAB: NIGHT`. Everything here is pure — no view instantiation, no GRDB, no
//  HealthKit. The loader is tested through `LabWindowSnapshot.assemble`, which
//  is the seam the middleware feeds.
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

// MARK: - Fixture helpers

/// A fixed, timezone-stable night: 2026-09-11 20:00 → 2026-09-12 10:00 local.
enum NightFixture {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London") ?? .current
        return calendar
    }

    /// The anchor day the night belongs to (the MORNING day).
    static var day: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 12))!
    }

    static func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    static var interval: DateInterval {
        DateInterval(start: at(11, 20), end: at(12, 10))
    }

    /// One reading every `stepMinutes` from `start` to `end`, flat at `value`.
    static func readings(from start: Date, to end: Date, every stepMinutes: Int, value: Int) -> [SensorGlucose] {
        var result: [SensorGlucose] = []
        var cursor = start
        while cursor <= end {
            result.append(SensorGlucose(timestamp: cursor, rawGlucoseValue: value, intGlucoseValue: value))
            cursor = cursor.addingTimeInterval(TimeInterval(stepMinutes * 60))
        }
        return result
    }
}

// MARK: - Lab window

@Suite("Lab window")
struct LabWindowTests {
    @Test("stream labels are unique and short enough for the POST strip")
    func labelsAreUniqueAndShort() {
        let labels = LabStream.allCases.map(\.label)
        #expect(Set(labels).count == labels.count, "duplicate POST labels: \(labels)")
        for label in labels {
            #expect(label.count <= 5, "\(label) is wider than the strip's 5-character budget")
        }
    }

    @Test("only the three body streams come from HealthKit")
    func sourceSplit() {
        let healthKit = LabStream.allCases.filter { $0.source == .healthKit }
        #expect(Set(healthKit) == Set([.heartRate, .sleep, .steps]))
    }

    @Test("coverage spans the first and last row of each stream")
    func coverageSpansRows() {
        let interval = NightFixture.interval
        let readings = NightFixture.readings(
            from: interval.start,
            to: interval.end,
            every: 5,
            value: 110
        )
        let meals = [MealEntry(timestamp: NightFixture.at(11, 19, 5), mealDescription: "dinner", carbsGrams: 80)]

        let snapshot = LabWindowSnapshot.assemble(
            raw: LabWindowRaw(
                readings: readings,
                bloodGlucose: [],
                meals: meals,
                deliveries: [],
                iobDeliveries: [],
                exercise: [],
                notes: []
            ),
            interval: interval,
            heartRate: [],
            sleep: [],
            heartRateAvailability: .available,
            sleepAvailability: .available
        )

        let glucoseCoverage = snapshot.coverage[.glucose]
        #expect(glucoseCoverage?.start == readings.first?.timestamp)
        #expect(glucoseCoverage?.end == readings.last?.timestamp)

        // The coverage learning: a secondary fetch must reach the primary
        // window. The 4h lead means the dinner row starts BEFORE the window.
        let mealCoverage = snapshot.coverage[.meals]
        #expect(mealCoverage?.start == meals.first?.timestamp)
        #expect(mealCoverage.map { $0.start < interval.start } == true)
    }

    @Test("every GRDB stream's coverage reaches the requested window")
    func grdbCoverageReachesWindow() {
        let interval = NightFixture.interval
        let lead = interval.start.addingTimeInterval(-4 * 3600)

        let snapshot = LabWindowSnapshot.assemble(
            raw: LabWindowRaw(
                readings: NightFixture.readings(from: interval.start, to: interval.end, every: 5, value: 110),
                bloodGlucose: [BloodGlucose(timestamp: interval.start, glucoseValue: 120),
                               BloodGlucose(timestamp: interval.end, glucoseValue: 130)],
                meals: [MealEntry(timestamp: lead, mealDescription: "a", carbsGrams: 10),
                        MealEntry(timestamp: interval.end, mealDescription: "b", carbsGrams: 10)],
                deliveries: [InsulinDelivery(starts: lead, ends: lead, units: 5, type: .mealBolus),
                             InsulinDelivery(starts: interval.end, ends: interval.end, units: 1, type: .correctionBolus)],
                iobDeliveries: [InsulinDelivery(starts: lead, ends: lead, units: 5, type: .mealBolus)],
                exercise: [ExerciseEntry(startTime: interval.start, endTime: interval.end, activityType: "Walk", durationMinutes: 30, activeCalories: nil, source: nil)],
                notes: [JournalNote(timestamp: interval.start, text: "slept badly"),
                        JournalNote(timestamp: interval.end, text: "groggy")]
            ),
            interval: interval,
            heartRate: [],
            sleep: [],
            heartRateAvailability: .available,
            sleepAvailability: .available
        )

        // `.iob` is deliberately excluded: its rows reach BACK a full DIA so an
        // evening bolus's tail can be drawn, and they are not expected to reach
        // the window's end. Its own contract is asserted below.
        let windowSpanning: Set<LabStream> = [.glucose, .bloodGlucose, .meals, .insulin, .exercise, .journalNotes]
        for stream in LabStream.allCases where stream.source == .grdb && windowSpanning.contains(stream) {
            guard let coverage = snapshot.coverage[stream] else {
                Issue.record("\(stream.label) returned no rows — the fetch window does not reach the requested one")
                continue
            }
            #expect(coverage.start <= interval.start, "\(stream.label) coverage starts after the window")
            #expect(coverage.end >= interval.end, "\(stream.label) coverage ends before the window")
        }

        // Every GRDB stream is accounted for — a new case must be classified,
        // not silently skipped.
        let classified = windowSpanning.union([.iob])
        for stream in LabStream.allCases where stream.source == .grdb {
            #expect(classified.contains(stream), "\(stream.label) has no coverage contract in this test")
        }

        #expect(snapshot.coverage[.iob]?.start == lead, "the IOB lead must reach back before the window")
    }

    @Test("a stream with no rows is empty, not loaded")
    func emptyStreams() {
        let interval = NightFixture.interval
        let snapshot = LabWindowSnapshot.assemble(
            raw: LabWindowRaw(
                readings: NightFixture.readings(from: interval.start, to: interval.end, every: 5, value: 110),
                bloodGlucose: [], meals: [], deliveries: [], iobDeliveries: [], exercise: [], notes: []
            ),
            interval: interval,
            heartRate: [],
            sleep: [],
            heartRateAvailability: .available,
            sleepAvailability: .available
        )

        #expect(snapshot.status[.meals] == .empty)
        #expect(snapshot.status[.exercise] == .empty)
        #expect(snapshot.status[.journalNotes] == .empty)
        #expect(snapshot.status[.heartRate] == .empty)
        #expect(snapshot.status[.sleep] == .empty)
        if case .loaded = snapshot.status[.glucose] {} else {
            Issue.record("glucose should be .loaded, got \(String(describing: snapshot.status[.glucose]))")
        }
    }

    @Test("steps are never read in this build")
    func stepsUnavailable() {
        let snapshot = LabWindowSnapshot.assemble(
            raw: LabWindowRaw(readings: [], bloodGlucose: [], meals: [], deliveries: [], iobDeliveries: [], exercise: [], notes: []),
            interval: NightFixture.interval,
            heartRate: [], sleep: [],
            heartRateAvailability: .available,
            sleepAvailability: .available
        )
        #expect(snapshot.status[.steps] == .unavailable)
    }

    @Test("a failed HealthKit stream leaves every GRDB stream loaded")
    func healthKitFailureIsIsolated() {
        let interval = NightFixture.interval
        let snapshot = LabWindowSnapshot.assemble(
            raw: LabWindowRaw(
                readings: NightFixture.readings(from: interval.start, to: interval.end, every: 5, value: 110),
                bloodGlucose: [],
                meals: [MealEntry(timestamp: interval.start, mealDescription: "a", carbsGrams: 10)],
                deliveries: [], iobDeliveries: [], exercise: [], notes: []
            ),
            interval: interval,
            heartRate: [], sleep: [],
            heartRateAvailability: .failed,
            sleepAvailability: .unavailable
        )

        #expect(snapshot.status[.heartRate] == .failed)
        #expect(snapshot.status[.sleep] == .unavailable)
        if case .loaded = snapshot.status[.glucose] {} else {
            Issue.record("a HealthKit failure must not sink the GRDB streams")
        }
        if case .loaded = snapshot.status[.meals] {} else {
            Issue.record("a HealthKit failure must not sink the GRDB streams")
        }
    }

    @Test("an empty snapshot still knows its interval")
    func emptySnapshotKeepsInterval() {
        let interval = NightFixture.interval
        let snapshot = LabWindowSnapshot.empty(interval: interval, status: .failed)
        #expect(snapshot.interval == interval)
        #expect(snapshot.coverage.isEmpty)
        for stream in LabStream.allCases {
            #expect(snapshot.status[stream] == .failed)
        }
    }
}

// MARK: - Night window

@Suite("Night window")
struct NightWindowTests {
    @Test("the night runs 20:00 the evening before to 10:00 on the chosen day")
    func intervalSpansMidnight() {
        let interval = NightWindow.interval(for: NightFixture.day, calendar: NightFixture.calendar)
        #expect(interval.start == NightFixture.at(11, 20))
        #expect(interval.end == NightFixture.at(12, 10))
        #expect(interval.duration == 14 * 3600)
    }

    @Test("midnight is inside the window")
    func midnightInside() {
        let interval = NightWindow.interval(for: NightFixture.day, calendar: NightFixture.calendar)
        let midnight = NightWindow.midnight(in: interval, calendar: NightFixture.calendar)
        #expect(midnight == NightFixture.at(12, 0))
    }

    @Test("setLabWindow stores and clears the snapshot")
    func reducerSetsAndClears() {
        var state: DirectState = makeState()
        #expect(state.labWindow == nil)

        let snapshot = LabWindowSnapshot.empty(interval: NightFixture.interval)
        reduce(&state, .setLabWindow(snapshot: snapshot))
        #expect(state.labWindow?.interval == NightFixture.interval)

        reduce(&state, .setLabWindow(snapshot: nil))
        #expect(state.labWindow == nil)
    }

    @Test("the lab window is transient — it never persists across an AppState init")
    func windowIsTransient() {
        let defaults = makeTestDefaults()
        var state: DirectState = AppState(defaults: defaults)
        reduce(&state, .setLabWindow(snapshot: .empty(interval: NightFixture.interval)))
        #expect(state.labWindow != nil)

        let reloaded = AppState(defaults: defaults)
        #expect(reloaded.labWindow == nil)
    }
}

// MARK: - Sleep stages

@Suite("Sleep stages")
struct SleepStageTests {
    @Test("HealthKit sleep-analysis values map to lab stages")
    func healthKitMapping() {
        // HKCategoryValueSleepAnalysis: inBed 0, asleepUnspecified 1, awake 2,
        // asleepCore 3, asleepDeep 4, asleepREM 5.
        #expect(SleepSample.Stage(healthKitValue: 0) == .inBed)
        #expect(SleepSample.Stage(healthKitValue: 1) == .unspecified)
        #expect(SleepSample.Stage(healthKitValue: 2) == .awake)
        #expect(SleepSample.Stage(healthKitValue: 3) == .core)
        #expect(SleepSample.Stage(healthKitValue: 4) == .deep)
        #expect(SleepSample.Stage(healthKitValue: 5) == .rem)
        #expect(SleepSample.Stage(healthKitValue: 99) == .unspecified)
    }

    @Test("only the asleep stages count as asleep")
    func asleepStages() {
        #expect(SleepSample.Stage.core.isAsleep)
        #expect(SleepSample.Stage.deep.isAsleep)
        #expect(SleepSample.Stage.rem.isAsleep)
        #expect(SleepSample.Stage.unspecified.isAsleep)
        #expect(SleepSample.Stage.awake.isAsleep == false)
        #expect(SleepSample.Stage.inBed.isAsleep == false)
    }
}

// MARK: - Night summary

@Suite("Night summary")
struct NightSummaryTests {
    /// In bed 23:10, asleep 23:20, two awake gaps (01:00–01:10, 03:00–03:20),
    /// wake 05:50 — the plan's fixture.
    static var sleep: [SleepSample] {
        [
            SleepSample(start: NightFixture.at(11, 23, 10), end: NightFixture.at(12, 5, 50), stage: .inBed),
            SleepSample(start: NightFixture.at(11, 23, 20), end: NightFixture.at(12, 1, 0), stage: .core),
            SleepSample(start: NightFixture.at(12, 1, 0), end: NightFixture.at(12, 1, 10), stage: .awake),
            SleepSample(start: NightFixture.at(12, 1, 10), end: NightFixture.at(12, 3, 0), stage: .core),
            SleepSample(start: NightFixture.at(12, 3, 0), end: NightFixture.at(12, 3, 20), stage: .awake),
            SleepSample(start: NightFixture.at(12, 3, 20), end: NightFixture.at(12, 5, 50), stage: .deep),
        ]
    }

    /// 112 mg/dL until 03:00, 152 after — a +40 rise by wake.
    static var readings: [SensorGlucose] {
        var result: [SensorGlucose] = []
        var cursor = NightFixture.at(11, 20)
        let end = NightFixture.at(12, 10)
        let step = NightFixture.at(12, 3, 0)
        while cursor <= end {
            let value = cursor < step ? 112 : 152
            result.append(SensorGlucose(timestamp: cursor, rawGlucoseValue: value, intGlucoseValue: value))
            cursor = cursor.addingTimeInterval(5 * 60)
        }
        return result
    }

    @Test("asleep minutes exclude the awake gaps")
    func asleepMinutesExcludeAwake() {
        let summary = NightSummary.make(sleep: Self.sleep, readings: Self.readings, unit: .mgdL)
        // 100 + 110 + 150 = 360 minutes asleep inside a 6h40 time in bed.
        #expect(summary.asleepMinutes == 360)
        #expect(summary.awakeCount == 2)
        #expect(summary.inBed == NightFixture.at(11, 23, 10))
        #expect(summary.asleep == NightFixture.at(11, 23, 20))
        #expect(summary.wake == NightFixture.at(12, 5, 50))
    }

    @Test("the rise by wake carries the sample size it came from")
    func riseCarriesN() {
        let summary = NightSummary.make(sleep: Self.sleep, readings: Self.readings, unit: .mgdL)

        #expect(summary.glucoseAtSleep?.value == 112)
        #expect(summary.glucoseAtWake?.value == 152)
        #expect(summary.riseByWake?.value == 40)
        // 23:20 → 05:50 at 5-minute cadence, inclusive of both ends.
        #expect(summary.riseByWake?.n == 79)
        #expect(summary.glucoseAtSleep?.n == 1)
    }

    @Test("mmol/L figures are converted, and their unit says so")
    func mmolConversion() {
        let summary = NightSummary.make(sleep: Self.sleep, readings: Self.readings, unit: .mmolL)
        #expect(summary.glucoseAtSleep?.unit == GlucoseUnit.mmolL.localizedDescription)
        let value = summary.glucoseAtSleep?.value ?? 0
        #expect(abs(value - 112.0 / 18.0182) < 0.05)
    }

    @Test("no sleep data means no sleep figures, and no crash")
    func noSleep() {
        let summary = NightSummary.make(sleep: [], readings: Self.readings, unit: .mgdL)
        #expect(summary.inBed == nil)
        #expect(summary.asleep == nil)
        #expect(summary.wake == nil)
        #expect(summary.asleepMinutes == 0)
        #expect(summary.awakeCount == 0)
        #expect(summary.riseByWake == nil)
    }

    @Test("an awake span outside the sleep period is not an awakening")
    func awakeOutsideSleepIgnored() {
        var samples = Self.sleep
        samples.append(SleepSample(start: NightFixture.at(11, 21, 0), end: NightFixture.at(11, 21, 30), stage: .awake))
        samples.append(SleepSample(start: NightFixture.at(12, 7, 0), end: NightFixture.at(12, 7, 30), stage: .awake))

        let summary = NightSummary.make(sleep: samples, readings: Self.readings, unit: .mgdL)
        #expect(summary.awakeCount == 2, "only awakenings BETWEEN falling asleep and waking count")
    }

    @Test("overlapping asleep spans are merged, never double-counted")
    func overlappingAsleepMerged() {
        let samples = [
            SleepSample(start: NightFixture.at(11, 23, 0), end: NightFixture.at(12, 1, 0), stage: .core),
            SleepSample(start: NightFixture.at(12, 0, 30), end: NightFixture.at(12, 2, 0), stage: .deep),
        ]
        let summary = NightSummary.make(sleep: samples, readings: Self.readings, unit: .mgdL)
        #expect(summary.asleepMinutes == 180, "23:00 → 02:00 is three hours, not three and a half")
    }
}

// MARK: - Night chart context

@Suite("Night chart context")
struct NightContextTests {
    @Test("the sleep band spans falling asleep to waking, with the awake gaps carved out")
    func bandAndGaps() {
        let context = LabNightContext.make(
            sleep: NightSummaryTests.sleep,
            readings: NightSummaryTests.readings,
            interval: NightFixture.interval,
            glucoseUnit: .mgdL,
            alarmLow: 80,
            calendar: NightFixture.calendar
        )

        #expect(context.sleepBand?.start == NightFixture.at(11, 23, 20))
        #expect(context.sleepBand?.end == NightFixture.at(12, 5, 50))
        #expect(context.awakeGaps.count == 2)
        #expect(context.awakeGaps.first?.start == NightFixture.at(12, 1, 0))
    }

    @Test("the midnight rule sits inside the window")
    func midnightRule() {
        let context = LabNightContext.make(
            sleep: [], readings: NightSummaryTests.readings,
            interval: NightFixture.interval, glucoseUnit: .mgdL, alarmLow: 80,
            calendar: NightFixture.calendar
        )
        #expect(context.midnight == NightFixture.at(12, 0))
    }

    @Test("the hypo mark is the first reading under the alarm low, in display units")
    func hypoMark() {
        var readings = NightSummaryTests.readings
        readings.append(SensorGlucose(timestamp: NightFixture.at(12, 2, 0), rawGlucoseValue: 62, intGlucoseValue: 62))
        readings.append(SensorGlucose(timestamp: NightFixture.at(12, 2, 30), rawGlucoseValue: 58, intGlucoseValue: 58))

        let context = LabNightContext.make(
            sleep: NightSummaryTests.sleep, readings: readings,
            interval: NightFixture.interval, glucoseUnit: .mgdL, alarmLow: 80,
            calendar: NightFixture.calendar
        )

        #expect(context.hypo?.time == NightFixture.at(12, 2, 0))
        #expect(context.hypo?.label == "T-0 62")
    }

    @Test("no reading under the alarm low means no hypo mark")
    func noHypo() {
        let context = LabNightContext.make(
            sleep: NightSummaryTests.sleep, readings: NightSummaryTests.readings,
            interval: NightFixture.interval, glucoseUnit: .mgdL, alarmLow: 80,
            calendar: NightFixture.calendar
        )
        #expect(context.hypo == nil)
    }
}

// MARK: - POST coverage strip

@Suite("POST coverage strip")
struct LabCoverageStripTests {
    private static func snapshot(
        readingCount: Int,
        meals: Int = 0,
        insulin: Int = 0,
        notes: Int = 0,
        heartRate: LabStreamAvailability = .available,
        sleep: LabStreamAvailability = .available,
        heartRateRows: Int = 0,
        sleepRows: Int = 0
    ) -> LabWindowSnapshot {
        let interval = NightFixture.interval
        var readings: [SensorGlucose] = []
        for index in 0 ..< readingCount {
            let time = interval.start.addingTimeInterval(TimeInterval(index * 5 * 60))
            readings.append(SensorGlucose(timestamp: time, rawGlucoseValue: 110, intGlucoseValue: 110))
        }
        return LabWindowSnapshot.assemble(
            raw: LabWindowRaw(
                readings: readings,
                bloodGlucose: [],
                meals: (0 ..< meals).map { MealEntry(timestamp: interval.start.addingTimeInterval(TimeInterval($0 * 600)), mealDescription: "m", carbsGrams: 40) },
                deliveries: (0 ..< insulin).map { InsulinDelivery(starts: interval.start.addingTimeInterval(TimeInterval($0 * 600)), ends: interval.start.addingTimeInterval(TimeInterval($0 * 600)), units: 2, type: .mealBolus) },
                iobDeliveries: [],
                exercise: [],
                notes: (0 ..< notes).map { JournalNote(timestamp: interval.start.addingTimeInterval(TimeInterval($0 * 600)), text: "n") }
            ),
            interval: interval,
            heartRate: (0 ..< heartRateRows).map { HeartRateSample(time: interval.start.addingTimeInterval(TimeInterval($0 * 3600)), bpm: 60) },
            sleep: (0 ..< sleepRows).map { SleepSample(start: interval.start.addingTimeInterval(TimeInterval($0 * 3600)), end: interval.start.addingTimeInterval(TimeInterval(($0 + 1) * 3600)), stage: .core) },
            heartRateAvailability: heartRate,
            sleepAvailability: sleep
        )
    }

    @Test("the strip's order is the prototype's")
    func order() {
        #expect(LabCoverage.postOrder == [.glucose, .insulin, .meals, .exercise, .heartRate, .sleep, .steps, .journalNotes])
    }

    @Test("glucose coverage is readings over the readings the interval could hold")
    func glucosePercent() {
        // 14 h at a 5-minute cadence is 168 expected readings; 161 is 96%.
        let cells = LabCoverage.cells(snapshot: Self.snapshot(readingCount: 161), sensorIntervalMinutes: 5)
        let glucose = cells.first { $0.stream == .glucose }
        #expect(glucose?.value == "96%")
        #expect(glucose?.tone == .loaded)
    }

    @Test("the 4-hour lead cannot inflate glucose coverage")
    func leadDoesNotInflateCoverage() {
        let interval = NightFixture.interval
        // 161 readings inside the window, plus a 4-hour lead's worth before it.
        var readings = (0 ..< 161).map { index in
            SensorGlucose(
                timestamp: interval.start.addingTimeInterval(TimeInterval(index * 5 * 60)),
                rawGlucoseValue: 110,
                intGlucoseValue: 110
            )
        }
        readings += (1 ... 48).map { index in
            SensorGlucose(
                timestamp: interval.start.addingTimeInterval(TimeInterval(-index * 5 * 60)),
                rawGlucoseValue: 110,
                intGlucoseValue: 110
            )
        }

        let snapshot = LabWindowSnapshot.assemble(
            raw: LabWindowRaw(readings: readings, bloodGlucose: [], meals: [], deliveries: [], iobDeliveries: [], exercise: [], notes: []),
            interval: interval,
            heartRate: [], sleep: [],
            heartRateAvailability: .available, sleepAvailability: .available
        )

        #expect(snapshot.readings.count == 209)
        #expect(snapshot.readingsInWindow.count == 161)
        let cells = LabCoverage.cells(snapshot: snapshot, sensorIntervalMinutes: 5)
        #expect(cells.first { $0.stream == .glucose }?.value == "96%", "the lead must not be counted as coverage")
    }

    @Test("coverage never reads over 100%")
    func glucosePercentClamped() {
        let cells = LabCoverage.cells(snapshot: Self.snapshot(readingCount: 200), sensorIntervalMinutes: 5)
        #expect(cells.first { $0.stream == .glucose }?.value == "100%")
    }

    @Test("event streams show their count, an empty one an em dash")
    func eventCounts() {
        let cells = LabCoverage.cells(snapshot: Self.snapshot(readingCount: 100, meals: 1, insulin: 2, notes: 1), sensorIntervalMinutes: 5)
        #expect(cells.first { $0.stream == .meals }?.value == "1")
        #expect(cells.first { $0.stream == .insulin }?.value == "2")
        #expect(cells.first { $0.stream == .journalNotes }?.value == "1")

        let exercise = cells.first { $0.stream == .exercise }
        #expect(exercise?.value == "—")
        #expect(exercise?.tone == .empty)
    }

    @Test("HealthKit streams tick when present, say n/a when never asked")
    func healthKitCells() {
        let present = LabCoverage.cells(
            snapshot: Self.snapshot(readingCount: 100, heartRateRows: 12, sleepRows: 6),
            sensorIntervalMinutes: 5
        )
        #expect(present.first { $0.stream == .heartRate }?.value == "✓")
        #expect(present.first { $0.stream == .sleep }?.value == "✓")

        let denied = LabCoverage.cells(
            snapshot: Self.snapshot(readingCount: 100, heartRate: .unavailable, sleep: .unavailable),
            sensorIntervalMinutes: 5
        )
        let sleepCell = denied.first { $0.stream == .sleep }
        #expect(sleepCell?.value == "n/a")
        #expect(sleepCell?.tone == .unavailable)
    }

    @Test("a failed stream shouts rather than lying about being empty")
    func failedCell() {
        let cells = LabCoverage.cells(
            snapshot: Self.snapshot(readingCount: 100, heartRate: .failed),
            sensorIntervalMinutes: 5
        )
        let heartRate = cells.first { $0.stream == .heartRate }
        #expect(heartRate?.value == "!")
        #expect(heartRate?.tone == .failed)
    }

    @Test("steps are always n/a in this build")
    func stepsCell() {
        let cells = LabCoverage.cells(snapshot: Self.snapshot(readingCount: 100), sensorIntervalMinutes: 5)
        let steps = cells.first { $0.stream == .steps }
        #expect(steps?.value == "n/a")
        #expect(steps?.tone == .unavailable)
    }

    @Test("a nonsensical sensor interval falls back to a one-minute cadence, never a divide by zero")
    func zeroInterval() {
        // `sensorInterval` defaults to 1, so clamping to 1 is the honest floor:
        // 100 readings across 14 h of once-a-minute slots is 12%, not 100%.
        let cells = LabCoverage.cells(snapshot: Self.snapshot(readingCount: 100), sensorIntervalMinutes: 0)
        #expect(cells.first { $0.stream == .glucose }?.value == "12%")

        let negative = LabCoverage.cells(snapshot: Self.snapshot(readingCount: 100), sensorIntervalMinutes: -5)
        #expect(negative.first { $0.stream == .glucose }?.value == "12%")
    }
}

// MARK: - Lab figures

@Suite("Lab figure")
struct LabFigureTests {
    @Test("a figure always carries its sample size")
    func figureCarriesN() {
        // Compile-time contract: `LabFigure` has no initializer without `n`.
        let figure = LabFigure(kind: .delta, value: 40, unit: "mg/dL", n: 79)
        #expect(figure.n == 79)
        #expect(figure.value == 40)
    }
}
