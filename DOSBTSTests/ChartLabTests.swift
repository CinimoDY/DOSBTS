//
//  ChartLabTests.swift
//  DOSBTSTests
//
//  Chart Lab P0 (DMNC-1504 / DMNC-1500): the lab gate, the lab report types,
//  the overlay seam P1–P5 fill, and the pure series builder behind
//  `LabChartView`. Everything here is pure — no view instantiation, no GRDB.
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

// MARK: - Chart Lab reducer

@Suite("Chart Lab reducer")
struct ChartLabReducerTests {
    @Test("the lab is off on a fresh install")
    func defaultsOff() {
        let state = makeState()
        #expect(state.showChartLab == false)
    }

    @Test("setShowChartLab toggles the gate")
    func togglesGate() {
        var state: DirectState = makeState()
        reduce(&state, .setShowChartLab(enabled: true))
        #expect(state.showChartLab == true)
        reduce(&state, .setShowChartLab(enabled: false))
        #expect(state.showChartLab == false)
    }

    @Test("turning the lab off strands no lab selection")
    func offResetsLabSelection() {
        var state: DirectState = makeState()
        reduce(&state, .setShowChartLab(enabled: true))
        reduce(&state, .setSelectedReportType(reportType: .labMeals))
        #expect(state.selectedReportType == .labMeals)

        reduce(&state, .setShowChartLab(enabled: false))
        #expect(state.selectedReportType == .glucose)
    }

    @Test("turning the lab off leaves a shipping selection alone")
    func offKeepsShippingSelection() {
        var state: DirectState = makeState()
        reduce(&state, .setSelectedReportType(reportType: .timeInRange))
        reduce(&state, .setShowChartLab(enabled: false))
        #expect(state.selectedReportType == .timeInRange)
    }

    @Test("turning the lab on never moves the selection")
    func onKeepsSelection() {
        var state: DirectState = makeState()
        reduce(&state, .setSelectedReportType(reportType: .statistics))
        reduce(&state, .setShowChartLab(enabled: true))
        #expect(state.selectedReportType == .statistics)
    }
}

// MARK: - Chart Lab report types

@Suite("Chart Lab report types")
struct ChartLabReportTypeTests {
    @Test("the row hides every lab tab when the lab is off")
    func visibleWithLabOff() {
        #expect(ReportType.visible(labEnabled: false) == [.glucose, .timeInRange, .statistics])
    }

    @Test("the lab tabs follow the three shipping tabs, in order")
    func visibleWithLabOn() {
        let visible = ReportType.visible(labEnabled: true)
        #expect(visible.prefix(3) == [.glucose, .timeInRange, .statistics])
        #expect(Array(visible.suffix(4)) == [.labMeals, .labNight, .labSweep, .labPatterns])
        #expect(visible.count == 7)
    }

    @Test("lab raw values are stable persistence keys")
    func rawValuesRoundTrip() {
        #expect(ReportType(rawValue: "labMeals") == .labMeals)
        #expect(ReportType(rawValue: "labNight") == .labNight)
        #expect(ReportType(rawValue: "labSweep") == .labSweep)
        #expect(ReportType(rawValue: "labPatterns") == .labPatterns)
        #expect(ReportType.labMeals.rawValue == "labMeals")
        #expect(ReportType.labNight.rawValue == "labNight")
        #expect(ReportType.labSweep.rawValue == "labSweep")
        #expect(ReportType.labPatterns.rawValue == "labPatterns")
    }

    @Test("isLab marks exactly the four experimental tabs")
    func isLabPerCase() {
        #expect(ReportType.glucose.isLab == false)
        #expect(ReportType.timeInRange.isLab == false)
        #expect(ReportType.statistics.isLab == false)
        #expect(ReportType.labMeals.isLab == true)
        #expect(ReportType.labNight.isLab == true)
        #expect(ReportType.labSweep.isLab == true)
        #expect(ReportType.labPatterns.isLab == true)
    }

    @Test("usesDayWindow picks the day chips for the aggregate tabs only")
    func usesDayWindowPerCase() {
        #expect(ReportType.glucose.usesDayWindow == false)
        #expect(ReportType.labMeals.usesDayWindow == false)
        #expect(ReportType.labNight.usesDayWindow == false)
        #expect(ReportType.timeInRange.usesDayWindow == true)
        #expect(ReportType.statistics.usesDayWindow == true)
        #expect(ReportType.labSweep.usesDayWindow == true)
        #expect(ReportType.labPatterns.usesDayWindow == true)
    }

    @Test("labels are the on-screen tab text")
    func labels() {
        #expect(ReportType.labMeals.label == "LAB: MEALS")
        #expect(ReportType.labNight.label == "LAB: NIGHT")
        #expect(ReportType.labSweep.label == "LAB: SWEEP")
        #expect(ReportType.labPatterns.label == "LAB: PATTERNS")
    }
}

// MARK: - Chart Lab overlay seam

@Suite("Chart Lab overlays")
struct ChartLabOverlayTests {
    @Test("shipping tabs layer nothing")
    func shippingTabsHaveNoOverlays() {
        #expect(ReportType.glucose.labOverlays.isEmpty)
        #expect(ReportType.timeInRange.labOverlays.isEmpty)
        #expect(ReportType.statistics.labOverlays.isEmpty)
    }

    @Test("LAB: SWEEP layers nothing on the lab chart (it draws its own surface)")
    func sweepHasNoOverlays() {
        #expect(ReportType.labSweep.labOverlays.isEmpty)
    }

    @Test("LAB: MEALS claims the meal-shaped overlays")
    func mealsClaimsMealOverlays() {
        #expect(ReportType.labMeals.labOverlays.contains(.carbSizedMeals))
        #expect(ReportType.labMeals.labOverlays.contains(.mealResponseRibbons))
    }

    // `LabOverlayMarks.marks(for:series:yMax:)` switches exhaustively, so the
    // compiler already guarantees every case has an arm. What a test can add is
    // that no case is orphaned from the UI: each one must be claimed by at least
    // one lab tab, or a P1–P5 worker fills an arm nothing ever switches on.
    @Test("every overlay case is claimed by at least one lab tab")
    func everyOverlayIsReachable() {
        let claimed = ReportType.allCases.reduce(into: Set<ChartLabOverlay>()) { acc, type in
            acc.formUnion(type.labOverlays)
        }
        #expect(claimed == Set(ChartLabOverlay.allCases))
    }
}

// MARK: - Lab chart series builder

@Suite("Lab chart series builder")
struct LabChartSeriesBuilderTests {
    /// Exact minute boundary (1_757_664_000 / 60 == 29_294_400), so the models'
    /// `toRounded(on: 1, .minute)` never shifts a fixture.
    private static let base = Date(timeIntervalSince1970: 1_757_664_000)

    private func inputs(
        sensorGlucose: [SensorGlucose] = [],
        bloodGlucose: [BloodGlucose] = [],
        meals: [MealEntry] = [],
        insulin: [InsulinDelivery] = [],
        iobDeliveries: [InsulinDelivery] = [],
        exercise: [ExerciseEntry] = [],
        heartRate: [HeartRateSample] = [],
        selectedDate: Date? = nil
    ) -> LabChartInputs {
        LabChartInputs(
            sensorGlucose: sensorGlucose,
            bloodGlucose: bloodGlucose,
            meals: meals,
            insulin: insulin,
            iobDeliveries: iobDeliveries,
            exercise: exercise,
            heartRate: heartRate,
            glucoseUnit: .mgdL,
            alarmLow: 80,
            alarmHigh: 180,
            bolusPreset: .rapidActing,
            basalDIAMinutes: 24 * 60,
            showSmoothed: false,
            smoothThreshold: Self.base,
            selectedDate: selectedDate,
            overlays: []
        )
    }

    private func reading(_ minutesFromBase: Int, _ value: Int) -> SensorGlucose {
        SensorGlucose(
            timestamp: Self.base.addingTimeInterval(TimeInterval(minutesFromBase * 60)),
            rawGlucoseValue: value,
            intGlucoseValue: value
        )
    }

    @Test("no glucose at all is an empty series")
    func emptyInputs() {
        let series = LabChartSeriesBuilder.build(inputs())
        #expect(series.isEmpty)
        #expect(series.readingCount == 0)
        #expect(series.glucoseSegments.isEmpty)
    }

    @Test("the live domain runs 15 minutes past the newest reading")
    func liveDomainExtends() {
        let series = LabChartSeriesBuilder.build(inputs(sensorGlucose: [reading(0, 100), reading(60, 140)]))
        #expect(series.domainStart == Self.base)
        #expect(series.domainEnd == Self.base.addingTimeInterval(75 * 60))
    }

    @Test("a picked day ends exactly at the newest reading")
    func pickedDayDomainStops() {
        let series = LabChartSeriesBuilder.build(
            inputs(sensorGlucose: [reading(0, 100), reading(60, 140)], selectedDate: Self.base)
        )
        #expect(series.domainEnd == Self.base.addingTimeInterval(60 * 60))
    }

    @Test("blood glucose widens the domain too")
    func bloodGlucoseCountsTowardsDomain() {
        let series = LabChartSeriesBuilder.build(
            inputs(
                sensorGlucose: [reading(30, 100)],
                bloodGlucose: [BloodGlucose(timestamp: Self.base, glucoseValue: 95)],
                selectedDate: Self.base
            )
        )
        #expect(series.domainStart == Self.base)
        #expect(series.domainEnd == Self.base.addingTimeInterval(30 * 60))
        #expect(series.isEmpty == false)
    }

    @Test("the cursor lookup table is keyed on whole minutes")
    func glucoseByMinuteIsMinuteAligned() {
        let series = LabChartSeriesBuilder.build(inputs(sensorGlucose: [reading(0, 100), reading(5, 120)]))
        #expect(series.glucoseByMinute.count == 2)
        for key in series.glucoseByMinute.keys {
            #expect(key == key.toRounded(on: 1, .minute))
        }
        #expect(series.glucoseByMinute[Self.base] != nil)
    }

    @Test("nearestGlucose reaches 3 minutes but not 7")
    func nearestGlucoseTolerance() {
        let series = LabChartSeriesBuilder.build(inputs(sensorGlucose: [reading(0, 100), reading(60, 140)]))
        let threeAway = Self.base.addingTimeInterval(3 * 60)
        let sevenAway = Self.base.addingTimeInterval(7 * 60)
        #expect(series.nearestGlucose(at: threeAway)?.value == 100)
        #expect(series.nearestGlucose(at: sevenAway) == nil)
    }

    @Test("IOB is sampled once a minute across the domain")
    func iobSampling() {
        let delivery = InsulinDelivery(
            starts: Self.base,
            ends: Self.base,
            units: 5,
            type: .mealBolus
        )
        let series = LabChartSeriesBuilder.build(
            inputs(
                sensorGlucose: [reading(0, 100), reading(60, 140)],
                iobDeliveries: [delivery],
                selectedDate: Self.base
            )
        )
        // 60 minutes of domain, inclusive of both ends.
        #expect(series.iob.count == 61)
        #expect(series.iob.first?.date == Self.base)
        #expect((series.iob.first?.total ?? 0) > 0)
    }

    @Test("no IOB deliveries means no IOB area")
    func iobEmptyWithoutDeliveries() {
        let series = LabChartSeriesBuilder.build(inputs(sensorGlucose: [reading(0, 100), reading(60, 140)]))
        #expect(series.iob.isEmpty)
    }

    @Test("the A→B summary carries its own sample size")
    func summaryOverRange() {
        let readings = [
            reading(0, 90),     // before A
            reading(10, 169),   // A
            reading(20, 152),
            reading(30, 206),
            reading(40, 201),   // B
            reading(50, 120)    // after B
        ]
        let insideMeal = MealEntry(timestamp: Self.base.addingTimeInterval(15 * 60), mealDescription: "Toast", carbsGrams: 60)
        let outsideMeal = MealEntry(timestamp: Self.base.addingTimeInterval(45 * 60), mealDescription: "Apple", carbsGrams: 25)
        let insideBolus = InsulinDelivery(
            starts: Self.base.addingTimeInterval(12 * 60),
            ends: Self.base.addingTimeInterval(12 * 60),
            units: 5,
            type: .mealBolus
        )
        let outsideBolus = InsulinDelivery(
            starts: Self.base.addingTimeInterval(48 * 60),
            ends: Self.base.addingTimeInterval(48 * 60),
            units: 3,
            type: .correctionBolus
        )

        let series = LabChartSeriesBuilder.build(
            inputs(
                sensorGlucose: readings,
                meals: [insideMeal, outsideMeal],
                insulin: [insideBolus, outsideBolus],
                selectedDate: Self.base
            )
        )

        let summary = series.summary(
            over: Self.base.addingTimeInterval(10 * 60)...Self.base.addingTimeInterval(40 * 60)
        )

        #expect(summary.readings == 4)
        #expect(summary.first == 169)
        #expect(summary.last == 201)
        #expect(summary.delta == 32)
        #expect(summary.min == 152)
        #expect(summary.max == 206)
        #expect(summary.carbsGrams == 60)
        #expect(summary.insulinUnits == 5)
    }

    @Test("an empty window reports n = 0 rather than a stale number")
    func summaryEmptyRange() {
        let series = LabChartSeriesBuilder.build(inputs(sensorGlucose: [reading(0, 100), reading(60, 140)]))
        let summary = series.summary(
            over: Self.base.addingTimeInterval(20 * 60)...Self.base.addingTimeInterval(30 * 60)
        )
        #expect(summary.readings == 0)
        #expect(summary.first == nil)
        #expect(summary.delta == nil)
        #expect(summary.carbsGrams == 0)
        #expect(summary.insulinUnits == 0)
    }

    @Test("mmol/L inputs come out of the builder in mmol/L")
    func mmolLSeries() {
        let mmolInputs = LabChartInputs(
            sensorGlucose: [reading(0, 180)],
            bloodGlucose: [],
            meals: [],
            insulin: [],
            iobDeliveries: [],
            exercise: [],
            heartRate: [],
            glucoseUnit: .mmolL,
            alarmLow: 80,
            alarmHigh: 180,
            bolusPreset: .rapidActing,
            basalDIAMinutes: 24 * 60,
            showSmoothed: false,
            smoothThreshold: Self.base,
            selectedDate: Self.base,
            overlays: []
        )
        let series = LabChartSeriesBuilder.build(mmolInputs)
        let value = series.glucoseByMinute[Self.base]?.value ?? 0
        #expect(value > 9.5 && value < 10.5)
    }
}

// MARK: - Lab cursor state

@Suite("Lab cursor state")
struct LabCursorStateTests {
    private static let base = Date(timeIntervalSince1970: 1_757_664_000)
    private let minRange: TimeInterval = 5 * 60

    private func at(_ minutes: Int) -> Date {
        Self.base.addingTimeInterval(TimeInterval(minutes * 60))
    }

    @Test("a press sets a single cursor and the release keeps it")
    func pressThenRelease() {
        var state = LabCursorState()
        state.apply(selection: at(10), minRange: minRange)
        #expect(state.cursor == at(10))
        #expect(state.range == nil)

        state.apply(selection: nil, minRange: minRange)
        #expect(state.cursor == at(10), "the sticky cursor must survive the release")
    }

    @Test("dragging inside one press moves the cursor instead of opening a range")
    func dragMovesCursor() {
        var state = LabCursorState()
        state.apply(selection: at(10), minRange: minRange)
        state.apply(selection: at(30), minRange: minRange)
        #expect(state.cursor == at(30))
        #expect(state.range == nil, "one press is one cursor, however far it travels")
    }

    @Test("a second press promotes the standing cursor to A and the new one to B")
    func secondPressOpensRange() {
        var state = LabCursorState()
        state.apply(selection: at(10), minRange: minRange)
        state.apply(selection: nil, minRange: minRange)

        state.apply(selection: at(40), minRange: minRange)
        #expect(state.range == at(10)...at(40))
        #expect(state.cursor == nil)
    }

    @Test("A and B order themselves, so measuring backwards works")
    func rangeOrdersItself() {
        var state = LabCursorState()
        state.apply(selection: at(40), minRange: minRange)
        state.apply(selection: nil, minRange: minRange)
        state.apply(selection: at(10), minRange: minRange)
        #expect(state.range == at(10)...at(40))
    }

    @Test("dragging the second press moves B")
    func dragMovesB() {
        var state = LabCursorState()
        state.apply(selection: at(10), minRange: minRange)
        state.apply(selection: nil, minRange: minRange)
        state.apply(selection: at(40), minRange: minRange)
        state.apply(selection: at(70), minRange: minRange)
        #expect(state.range == at(10)...at(70))
    }

    @Test("a third press starts over with a single cursor")
    func thirdPressResets() {
        var state = LabCursorState()
        state.apply(selection: at(10), minRange: minRange)
        state.apply(selection: nil, minRange: minRange)
        state.apply(selection: at(40), minRange: minRange)
        state.apply(selection: nil, minRange: minRange)

        state.apply(selection: at(80), minRange: minRange)
        #expect(state.range == nil)
        #expect(state.cursor == at(80))
    }

    @Test("a second press closer than minRange is a re-scrub, not a measurement")
    func nearSecondPressIsRescrub() {
        var state = LabCursorState()
        state.apply(selection: at(10), minRange: minRange)
        state.apply(selection: nil, minRange: minRange)

        state.apply(selection: at(12), minRange: minRange)
        #expect(state.range == nil)
        #expect(state.cursor == at(12))
    }

    @Test("clear empties both, and the next press starts fresh")
    func clearResets() {
        var state = LabCursorState()
        state.apply(selection: at(10), minRange: minRange)
        state.apply(selection: nil, minRange: minRange)
        state.apply(selection: at(40), minRange: minRange)
        state.apply(selection: nil, minRange: minRange)
        #expect(state.range != nil)

        state.clear()
        #expect(state.cursor == nil)
        #expect(state.range == nil)
        #expect(state.isEmpty)

        state.apply(selection: at(90), minRange: minRange)
        #expect(state.cursor == at(90))
        #expect(state.range == nil)
    }
}

// MARK: - Lab chart math

@Suite("Lab chart math")
struct LabChartMathTests {
    private static let base = Date(timeIntervalSince1970: 1_757_664_000)

    private func at(_ minutes: Int) -> Date {
        Self.base.addingTimeInterval(TimeInterval(minutes * 60))
    }

    @Test("chart height is clamped both ways")
    func chartHeightClamps() {
        #expect(LabChartMath.chartHeight(available: 500, minimum: 140, maximum: 310) == 310)
        #expect(LabChartMath.chartHeight(available: 80, minimum: 140, maximum: 310) == 140)
        #expect(LabChartMath.chartHeight(available: 220, minimum: 140, maximum: 310) == 220)
    }

    @Test("an unknown zoom level falls back, a known one passes through")
    func visibleHoursFallback() {
        #expect(LabChartMath.visibleHours(zoomLevel: 6, fallback: 3) == 6)
        #expect(LabChartMath.visibleHours(zoomLevel: 24, fallback: 3) == 24)
        #expect(LabChartMath.visibleHours(zoomLevel: 5, fallback: 3) == 3)
        #expect(LabChartMath.visibleHours(zoomLevel: 0, fallback: 3) == 3)
    }

    @Test("hour labels thin out with the window, mirroring ChartView.Config.zoomLevels")
    func labelEvery() {
        #expect(LabChartMath.labelEvery(visibleHours: 3) == 1)
        #expect(LabChartMath.labelEvery(visibleHours: 6) == 2)
        #expect(LabChartMath.labelEvery(visibleHours: 12) == 3)
        #expect(LabChartMath.labelEvery(visibleHours: 24) == 4)
        #expect(LabChartMath.labelEvery(visibleHours: 7) == 1)
    }

    @Test("yMax is a floor the data can push past, never a ceiling that clips")
    func yMaxFloor() {
        #expect(LabChartMath.yMax(floor: 300, plotted: [80, 120, 260]) == 300)
        #expect(LabChartMath.yMax(floor: 300, plotted: []) == 300)
        // A hyper above the floor must stay visible — SensorGlucose clamps at 501.
        #expect(LabChartMath.yMax(floor: 300, plotted: [80, 412.4]) == 413)
        #expect(LabChartMath.yMax(floor: 18, plotted: [4.2, 22.7]) == 23)
    }

    @Test("the follow edge is the leading edge, clamped to the domain start")
    func followEdge() {
        #expect(LabChartMath.followEdge(domainStart: at(0), domainEnd: at(600), visibleDuration: 3600) == at(540))
        // A domain shorter than the window cannot scroll behind its own start.
        #expect(LabChartMath.followEdge(domainStart: at(0), domainEnd: at(30), visibleDuration: 3600) == at(0))
    }

    @Test("follow is on while the newest reading is in view")
    func isFollowing() {
        let end = at(600)
        #expect(LabChartMath.isFollowing(scrollPosition: at(540), domainEnd: end, visibleDuration: 3600, slack: 60))
        #expect(LabChartMath.isFollowing(scrollPosition: at(539), domainEnd: end, visibleDuration: 3600, slack: 60))
        #expect(!LabChartMath.isFollowing(scrollPosition: at(400), domainEnd: end, visibleDuration: 3600, slack: 60))
    }

    // The bug this pins: the store hands the chart a ROLLING 24 h window
    // (SensorGlucoseStore.swift:328, `datetime('now','-24 hours')`), so in steady
    // state one reading enters as one ages out and an array-length delta is 0
    // forever — the nub would never appear. Count by timestamp instead.
    @Test("unseen readings are counted by timestamp, not by array length")
    func unseenSurvivesTheRollingWindow() {
        let before = [at(0), at(5), at(10), at(15)]
        let after = [at(5), at(10), at(15), at(20)]   // one in, one out — same count

        let newestSeen = before.last
        #expect(before.count == after.count, "the fixture must roll, not grow")
        #expect(LabChartMath.unseenCount(readingTimes: after, newerThan: newestSeen) == 1)
    }

    @Test("unseen counts every reading past the mark, and none before it")
    func unseenCounting() {
        let times = [at(0), at(5), at(10), at(15)]
        #expect(LabChartMath.unseenCount(readingTimes: times, newerThan: at(5)) == 2)
        #expect(LabChartMath.unseenCount(readingTimes: times, newerThan: at(15)) == 0)
        #expect(LabChartMath.unseenCount(readingTimes: times, newerThan: nil) == 0, "no mark yet means nothing is unseen")
    }

    @Test("the A→B minimum is a screen distance, not a fixed duration")
    func minRangeIsScreenDistance() {
        // 12 pt of a 300 pt plot showing 3 h == 432 s; the same 12 pt of a 24 h
        // window is eight times longer in time.
        let threeHours = LabChartMath.minRangeSeconds(visibleDuration: 3 * 3600, plotWidth: 300, points: 12)
        let twentyFour = LabChartMath.minRangeSeconds(visibleDuration: 24 * 3600, plotWidth: 300, points: 12)
        #expect(abs(threeHours - 432) < 0.5)
        #expect(abs(twentyFour - threeHours * 8) < 1)
        // Degenerate width must not divide by zero.
        #expect(LabChartMath.minRangeSeconds(visibleDuration: 3600, plotWidth: 0, points: 12) > 0)
    }

    @Test("a clear tap is short and still; a scrub press is neither")
    func clearTapDiscrimination() {
        #expect(LabChartMath.isClearTap(held: 0.1, translation: .zero, maxDuration: 0.35, maxDistance: 10))
        #expect(!LabChartMath.isClearTap(held: 0.8, translation: .zero, maxDuration: 0.35, maxDistance: 10))
        #expect(!LabChartMath.isClearTap(held: 0.1, translation: CGSize(width: 40, height: 0), maxDuration: 0.35, maxDistance: 10))
        #expect(!LabChartMath.isClearTap(held: 0.1, translation: CGSize(width: 0, height: 40), maxDuration: 0.35, maxDistance: 10))
    }
}

// MARK: - Lab detents

@Suite("Lab detents")
struct LabDetentTests {
    @Test("a repeated key is silent; a changed key ticks")
    func onlyFiresOnChange() {
        #expect(LabDetent.feedback(newKey: "meal-1", previousKey: nil, isNight: false) == .light)
        #expect(LabDetent.feedback(newKey: "meal-1", previousKey: "meal-1", isNight: false) == nil)
        #expect(LabDetent.feedback(newKey: nil, previousKey: "meal-1", isNight: false) == nil)
    }

    @Test("alarm bounds tick harder than events")
    func boundsAreMedium() {
        #expect(LabDetent.feedback(newKey: "low", previousKey: nil, isNight: false) == .medium)
        #expect(LabDetent.feedback(newKey: "high", previousKey: nil, isNight: false) == .medium)
        #expect(LabDetent.feedback(newKey: "insulin-7", previousKey: nil, isNight: false) == .light)
    }

    @Test("the night profile silences every detent")
    func nightGate() {
        #expect(LabDetent.feedback(newKey: "meal-1", previousKey: nil, isNight: true) == nil)
        #expect(LabDetent.feedback(newKey: "low", previousKey: nil, isNight: true) == nil)
    }
}

// MARK: - Lab follow status

@Suite("Lab follow status")
struct LabFollowStatusTests {
    @Test("following carries no unseen count")
    func following() {
        #expect(LabFollowStatus.following.isFollowing)
        #expect(LabFollowStatus.following.unseen == 0)
    }

    @Test("detached carries its own n")
    func detached() {
        let status = LabFollowStatus.detached(unseen: 3)
        #expect(!status.isFollowing)
        #expect(status.unseen == 3)
    }
}

// MARK: - Unclamped insulin (sensor-gap regression)

@Suite("Lab series, unclamped insulin")
struct LabInsulinClampTests {
    private static let base = Date(timeIntervalSince1970: 1_757_664_000)

    private func reading(_ minutesFromBase: Int, _ value: Int) -> SensorGlucose {
        SensorGlucose(
            timestamp: Self.base.addingTimeInterval(TimeInterval(minutesFromBase * 60)),
            rawGlucoseValue: value,
            intGlucoseValue: value
        )
    }

    private func dose(_ minutesFromBase: Int, _ units: Double, _ type: InsulinType) -> InsulinDelivery {
        let at = Self.base.addingTimeInterval(TimeInterval(minutesFromBase * 60))
        return InsulinDelivery(starts: at, ends: at, units: units, type: type)
    }

    /// A sensor gap: two deliveries are hours older than the first reading, so
    /// `InsulinDelivery.toDatapoint(minDate:maxDate:)` CLAMPS their `starts` to
    /// `domainStart`. Reading the summary off the clamped datapoints piled them
    /// all onto the domain's first minute.
    private func gapSeries() -> LabChartSeries {
        LabChartSeriesBuilder.build(
            LabChartInputs(
                sensorGlucose: [reading(0, 100), reading(60, 140)],
                bloodGlucose: [],
                meals: [],
                insulin: [dose(-240, 9, .mealBolus), dose(-180, 5, .correctionBolus), dose(20, 4, .correctionBolus)],
                iobDeliveries: [],
                exercise: [],
                heartRate: [],
                glucoseUnit: .mgdL,
                alarmLow: 80,
                alarmHigh: 180,
                bolusPreset: .rapidActing,
                basalDIAMinutes: 24 * 60,
                showSmoothed: false,
                smoothThreshold: Self.base,
                selectedDate: Self.base,
                overlays: []
            )
        )
    }

    @Test("doses from before the domain never land in an A→B total")
    func clampedDosesStayOutOfTheSummary() {
        let series = gapSeries()
        let firstHalf = series.summary(over: Self.base...Self.base.addingTimeInterval(30 * 60))
        #expect(firstHalf.insulinUnits == 4, "only the in-window 4 U correction counts")

        let wholeDomain = series.summary(over: Self.base...Self.base.addingTimeInterval(60 * 60))
        #expect(wholeDomain.insulinUnits == 4, "the two pre-domain doses are not in the domain either")
    }

    @Test("a clamped dose does not invent a detent at the domain start")
    func clampedDosesStayOutOfTheDetents() {
        let series = gapSeries()
        #expect(series.detentKey(at: Self.base, alarmLow: 80, alarmHigh: 180, window: 2 * 60) == nil)
    }

    @Test("the real dose still detents at its own time")
    func realDoseStillDetents() {
        let series = gapSeries()
        let key = series.detentKey(
            at: Self.base.addingTimeInterval(20 * 60),
            alarmLow: 80,
            alarmHigh: 180,
            window: 2 * 60
        )
        #expect(key?.hasPrefix("insulin-") == true)
    }

    @Test("the basal bars still draw against the clamped domain")
    func basalBarsKeepTheirClamp() {
        let series = gapSeries()
        // The drawing datapoints are deliberately still clamped — that is what
        // keeps an out-of-domain basal bar inside the plot.
        #expect(series.insulin.allSatisfy { $0.starts >= series.domainStart })
        #expect(series.insulinDoses.contains { $0.starts < series.domainStart })
    }
}

// MARK: - Chart Lab gate coherence

@Suite("Chart Lab gate coherence")
struct ChartLabGateTests {
    @Test("turning the lab off persists the reset, not just the in-memory value")
    func offResetPersists() {
        let defaults = makeTestDefaults()
        var state: DirectState = AppState(defaults: defaults)

        reduce(&state, .setShowChartLab(enabled: true))
        reduce(&state, .setSelectedReportType(reportType: .labMeals))
        #expect(defaults.selectedReportType == .labMeals)

        reduce(&state, .setShowChartLab(enabled: false))
        #expect(defaults.selectedReportType == .glucose, "a relaunch must not restore a tab the row no longer shows")
        #expect(defaults.showChartLab == false)
    }

    @Test("a lab report type cannot be selected while the gate is off")
    func labSelectionRefusedWhileGateOff() {
        var state: DirectState = makeState()
        reduce(&state, .setSelectedReportType(reportType: .labMeals))
        #expect(state.selectedReportType == .glucose)

        reduce(&state, .setShowChartLab(enabled: true))
        reduce(&state, .setSelectedReportType(reportType: .labNight))
        #expect(state.selectedReportType == .labNight)
    }

    @Test("launch normalises a lab selection stranded by a gate that is off")
    func initNormalisesStrandedSelection() {
        let defaults = makeTestDefaults()
        defaults.selectedReportType = .labMeals
        defaults.showChartLab = false

        let state = AppState(defaults: defaults)
        #expect(state.selectedReportType == .glucose)
        #expect(defaults.selectedReportType == .glucose, "the stranded key is cleared, not just masked")
    }

    @Test("launch leaves a lab selection alone while the gate is on")
    func initKeepsValidLabSelection() {
        let defaults = makeTestDefaults()
        defaults.selectedReportType = .labSweep
        defaults.showChartLab = true

        let state = AppState(defaults: defaults)
        #expect(state.selectedReportType == .labSweep)
    }
}

// MARK: - Readout height source pin

@Suite("Lab readout height")
struct LabReadoutHeightTests {
    // #filePath → …/DOSBTSTests/ChartLabTests.swift → repo root two levels up.
    private static var labChartViewSource: String {
        get throws {
            let root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            return try String(
                contentsOf: root.appendingPathComponent("App/Views/Overview/Lab/LabChartView.swift"),
                encoding: .utf8
            )
        }
    }

    /// The readout must never change height between its three states
    /// (swiftui-viewbuilder-branch-height-mismatch). Structurally that means ONE
    /// height, applied outside the branches — a per-branch `.frame(height:)`
    /// would reintroduce the jump this pins against.
    @Test("the pinned height is applied once, outside the state branches")
    func heightAppliedOnceOutsideTheBranches() throws {
        let source = try Self.labChartViewSource
        #expect(source.contains("pinnedHeight: Config.readoutHeight"), "the strip is handed the pinned constant")

        let applications = source.components(separatedBy: ".frame(height: pinnedHeight)").count - 1
        #expect(applications == 1, "found \(applications) pinned-height applications; the readout must apply exactly one, outside its branches")
    }
}

// MARK: - Readout segments

@Suite("Lab readout segments")
struct LabReadoutSegmentTests {
    private func fmt(_ value: Double) -> String { String(Int(value)) }
    private func units(_ value: Double) -> String { String(format: "%.1fU", value) }

    private func summary(
        first: Double? = 169, last: Double? = 201, min: Double? = 152, max: Double? = 206,
        delta: Double? = 32, readings: Int = 20, carbs: Double = 60, insulin: Double = 5
    ) -> LabRangeSummary {
        LabRangeSummary(
            first: first, last: last, min: min, max: max, delta: delta,
            readings: readings, carbsGrams: carbs, insulinUnits: insulin,
            heartRateFirst: nil, heartRateLast: nil
        )
    }

    @Test("the A→B line reads value, delta, min/max, insulin, carbs, then n")
    func fullLine() {
        let segments = summary().readoutSegments(format: fmt, units: units)
        #expect(segments.map(\.text) == [
            "G 169→201", "(+32)", "MIN 152 · MAX 206", "IN 5.0U", "CARBS 60g", "n=20"
        ])
    }

    @Test("n is always last, and always present")
    func sampleSizeAlwaysLast() {
        #expect(summary().readoutSegments(format: fmt, units: units).last?.text == "n=20")
        #expect(summary().readoutSegments(format: fmt, units: units).last?.emphasis == .sampleSize)
        // An empty window still says so rather than saying nothing.
        #expect(LabRangeSummary.none.readoutSegments(format: fmt, units: units).map(\.text) == ["n=0"])
    }

    @Test("a window with no doses and no carbs omits them rather than printing zero")
    func zeroesAreOmitted() {
        let segments = summary(carbs: 0, insulin: 0).readoutSegments(format: fmt, units: units)
        #expect(!segments.contains { $0.text.hasPrefix("IN ") })
        #expect(!segments.contains { $0.text.hasPrefix("CARBS ") })
    }

    @Test("a falling range carries its own minus, a rising one a plus")
    func deltaSign() {
        let rising = summary(delta: 32).readoutSegments(format: fmt, units: units)
        #expect(rising.contains { $0.text == "(+32)" && $0.emphasis == .delta })

        let falling = summary(first: 201, last: 169, delta: -32).readoutSegments(format: fmt, units: units)
        #expect(falling.contains { $0.text == "(-32)" })
    }
}
