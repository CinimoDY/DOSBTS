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
