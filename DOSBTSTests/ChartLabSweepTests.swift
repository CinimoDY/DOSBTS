//
//  ChartLabSweepTests.swift
//  DOSBTSTests
//
//  Chart Lab P3 (DMNC-1503): `LAB: SWEEP` — the event-locked response overlay.
//  Everything pinned here is pure: the sweep builder, the per-bin percentile
//  bands, the carb buckets, the twin finder, the LAPS line, the y-domain floor,
//  the 90-day read cap, and the transient-state reducer. No view instantiation,
//  no GRDB.
//
//  The parity suite is the load-bearing one: `SweepStatistics` re-implements the
//  baseline/peak/confounder rules that `MealOverlayLogic` owns (it has to — the
//  builder lives in `Library/`, which the widget target compiles, and
//  `MealOverlayLogic` lives under `App/`). These tests are what fails if the two
//  ever drift apart.
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

/// A fixed calendar so time-of-day and age-in-days assertions never depend on
/// the machine's locale or time zone.
private let testCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    if let utc = TimeZone(identifier: "UTC") { calendar.timeZone = utc }
    return calendar
}()

/// 2026-09-12 18:00 UTC — a fixed "now" for every fixture.
private let fixedNow = Date(timeIntervalSince1970: 1_789_495_200)

private func minutes(_ value: Int) -> TimeInterval { TimeInterval(value * 60) }

/// A meal `daysAgo` days back at the same wall-clock time, shifted by `minuteOffset`.
private func mealTime(daysAgo: Int, minuteOffset: Int = 0) -> Date {
    let base = testCalendar.date(byAdding: .day, value: -daysAgo, to: fixedNow) ?? fixedNow
    return base.addingTimeInterval(minutes(minuteOffset))
}

/// Readings every 5 minutes from `fromMinute` to `toMinute` relative to `anchor`,
/// whose value is `baseValue + shape(minute)`.
private func readings(
    anchor: Date,
    from fromMinute: Int,
    to toMinute: Int,
    baseValue: Int,
    shape: (Int) -> Int = { _ in 0 }
) -> [SensorGlucose] {
    stride(from: fromMinute, through: toMinute, by: 5).map { minute in
        let value = baseValue + shape(minute)
        return SensorGlucose(
            timestamp: anchor.addingTimeInterval(minutes(minute)),
            rawGlucoseValue: value,
            intGlucoseValue: value
        )
    }
}

private func makeMeal(at time: Date, carbs: Double?, name: String = "Dinner") -> MealEntry {
    MealEntry(timestamp: time, mealDescription: name, carbsGrams: carbs)
}

/// A hand-built sweep, for the pure consumers (twins, formatter) that take
/// sweeps rather than raw rows.
private func makeSweep(
    id: UUID = UUID(),
    mealTime: Date,
    carbs: Double?,
    name: String = "Dinner",
    minutesOfDay: Int = 12 * 60,
    ageDays: Int = 1,
    isClean: Bool = true,
    isInProgress: Bool = false,
    delta: Int? = 40,
    peakMinutes: Int? = 50,
    points: [SweepPoint] = [],
    n: Int = 24
) -> MealSweep {
    MealSweep(
        id: id,
        mealTime: mealTime,
        mealDescription: name,
        carbs: carbs,
        ageDays: ageDays,
        minutesOfDay: minutesOfDay,
        baseline: 110,
        points: points,
        isClean: isClean,
        exclusion: isClean ? nil : .confounded,
        isInProgress: isInProgress,
        delta: delta,
        peakMinutes: peakMinutes,
        n: n
    )
}

// MARK: - Sweep statistics

@Suite("Sweep statistics")
struct SweepStatisticsTests {

    @Test("points land on 5-minute steps across −30…+240, as deltas from the baseline")
    func fiveMinuteSteps() {
        let time = mealTime(daysAgo: 2)
        let meal = makeMeal(at: time, carbs: 60)
        let rows = readings(anchor: time, from: -30, to: 240, baseValue: 100) { minute in
            max(0, minute)  // +1 mg/dL per minute after t=0
        }

        let sweeps = SweepStatistics.build(
            meals: [meal], readings: rows, deliveries: [], exercise: [],
            now: fixedNow, calendar: testCalendar
        )

        #expect(sweeps.count == 1)
        let sweep = try? #require(sweeps.first)
        guard let sweep else { return }

        // −30…240 inclusive on a 5-minute stride is 55 points.
        #expect(sweep.points.count == 55)
        #expect(sweep.points.first?.minute == -30)
        #expect(sweep.points.last?.minute == 240)
        // Baseline is the last reading strictly before t=0 → the t−5 reading, value 100.
        #expect(sweep.baseline == 100)
        #expect(sweep.points.first(where: { $0.minute == 0 })?.delta == 0)
        #expect(sweep.points.first(where: { $0.minute == 60 })?.delta == 60)
        #expect(sweep.points.first(where: { $0.minute == -30 })?.delta == 0)
    }

    @Test("the baseline is the LAST reading in [t−15, t), not the earliest")
    func baselineIsLastBeforeMeal() {
        let time = mealTime(daysAgo: 2)
        let meal = makeMeal(at: time, carbs: 60)
        var rows: [SensorGlucose] = [
            SensorGlucose(timestamp: time.addingTimeInterval(minutes(-14)), rawGlucoseValue: 90, intGlucoseValue: 90),
            SensorGlucose(timestamp: time.addingTimeInterval(minutes(-5)), rawGlucoseValue: 120, intGlucoseValue: 120)
        ]
        rows += readings(anchor: time, from: 0, to: 120, baseValue: 150)

        let sweeps = SweepStatistics.build(
            meals: [meal], readings: rows, deliveries: [], exercise: [],
            now: fixedNow, calendar: testCalendar
        )

        #expect(sweeps.first?.baseline == 120)
        #expect(sweeps.first?.delta == 30)
    }

    @Test("no pre-meal reading → the first in-window reading is the reference, and the sweep is not clean")
    func noBaselineFallsBack() {
        let time = mealTime(daysAgo: 2)
        let meal = makeMeal(at: time, carbs: 60)
        let rows = readings(anchor: time, from: 0, to: 120, baseValue: 100) { max(0, $0) }

        let sweeps = SweepStatistics.build(
            meals: [meal], readings: rows, deliveries: [], exercise: [],
            now: fixedNow, calendar: testCalendar
        )

        #expect(sweeps.first?.baseline == nil)
        #expect(sweeps.first?.delta == 120)
        #expect(sweeps.first?.isClean == false)
        #expect(sweeps.first?.exclusion == .noBaseline)
    }

    @Test("fewer than 4 readings in the window is insufficient data, not a clean sweep")
    func lowReadingCount() {
        let time = mealTime(daysAgo: 2)
        let meal = makeMeal(at: time, carbs: 60)
        let rows = [
            SensorGlucose(timestamp: time.addingTimeInterval(minutes(-5)), rawGlucoseValue: 100, intGlucoseValue: 100),
            SensorGlucose(timestamp: time.addingTimeInterval(minutes(5)), rawGlucoseValue: 110, intGlucoseValue: 110),
            SensorGlucose(timestamp: time.addingTimeInterval(minutes(10)), rawGlucoseValue: 130, intGlucoseValue: 130),
            SensorGlucose(timestamp: time.addingTimeInterval(minutes(15)), rawGlucoseValue: 140, intGlucoseValue: 140)
        ]

        let sweeps = SweepStatistics.build(
            meals: [meal], readings: rows, deliveries: [], exercise: [],
            now: fixedNow, calendar: testCalendar
        )

        #expect(sweeps.first?.n == 3)
        #expect(sweeps.first?.isClean == false)
        #expect(sweeps.first?.exclusion == .insufficientData)
    }

    @Test("a correction bolus inside the 2 h window confounds the sweep")
    func correctionBolusConfounds() {
        let time = mealTime(daysAgo: 2)
        let meal = makeMeal(at: time, carbs: 60)
        let rows = readings(anchor: time, from: -30, to: 240, baseValue: 100) { max(0, $0) }
        let correction = InsulinDelivery(
            starts: time.addingTimeInterval(minutes(30)),
            ends: time.addingTimeInterval(minutes(30)),
            units: 2, type: .correctionBolus
        )

        let sweeps = SweepStatistics.build(
            meals: [meal], readings: rows, deliveries: [correction], exercise: [],
            now: fixedNow, calendar: testCalendar
        )

        #expect(sweeps.first?.isClean == false)
        #expect(sweeps.first?.exclusion == .confounded)
    }

    @Test("a meal bolus does NOT confound the sweep")
    func mealBolusDoesNotConfound() {
        let time = mealTime(daysAgo: 2)
        let meal = makeMeal(at: time, carbs: 60)
        let rows = readings(anchor: time, from: -30, to: 240, baseValue: 100) { max(0, $0) }
        let bolus = InsulinDelivery(starts: time, ends: time, units: 5, type: .mealBolus)

        let sweeps = SweepStatistics.build(
            meals: [meal], readings: rows, deliveries: [bolus], exercise: [],
            now: fixedNow, calendar: testCalendar
        )

        #expect(sweeps.first?.isClean == true)
        #expect(sweeps.first?.exclusion == nil)
    }

    @Test("overlapping exercise and a stacked meal both confound the sweep")
    func exerciseAndStackingConfound() {
        let time = mealTime(daysAgo: 2)
        let meal = makeMeal(at: time, carbs: 60)
        let rows = readings(anchor: time, from: -30, to: 240, baseValue: 100) { max(0, $0) }

        let run = ExerciseEntry(
            startTime: time.addingTimeInterval(minutes(45)),
            endTime: time.addingTimeInterval(minutes(75)),
            activityType: "Running", durationMinutes: 30, activeCalories: nil, source: nil
        )
        let withExercise = SweepStatistics.build(
            meals: [meal], readings: rows, deliveries: [], exercise: [run],
            now: fixedNow, calendar: testCalendar
        )
        #expect(withExercise.first?.isClean == false)

        let snack = makeMeal(at: time.addingTimeInterval(minutes(40)), carbs: 20, name: "Snack")
        let withStack = SweepStatistics.build(
            meals: [meal, snack], readings: rows, deliveries: [], exercise: [],
            now: fixedNow, calendar: testCalendar
        )
        let target = withStack.first(where: { $0.id == meal.id })
        #expect(target?.isClean == false)
        #expect(target?.exclusion == .confounded)
    }

    @Test("delta and peak come from the 2 h response window, not the 4 h trace")
    func deltaFromTwoHourWindow() {
        let time = mealTime(daysAgo: 2)
        let meal = makeMeal(at: time, carbs: 60)
        // Rises to +60 at t+60, falls back, then a second (later) rise at t+180
        // that must NOT become the peak.
        let rows = readings(anchor: time, from: -30, to: 240, baseValue: 100) { minute in
            switch minute {
            case ..<0: return 0
            case 0...120: return 60 - abs(minute - 60)
            default: return 200
            }
        }

        let sweeps = SweepStatistics.build(
            meals: [meal], readings: rows, deliveries: [], exercise: [],
            now: fixedNow, calendar: testCalendar
        )

        #expect(sweeps.first?.delta == 60)
        #expect(sweeps.first?.peakMinutes == 60)
        // The trace still runs out to +4 h.
        #expect(sweeps.first?.points.last?.minute == 240)
    }

    @Test("an in-progress sweep stops at now and is flagged")
    func inProgressStopsAtNow() {
        let time = fixedNow.addingTimeInterval(minutes(-40))
        let meal = makeMeal(at: time, carbs: 60)
        let rows = readings(anchor: time, from: -30, to: 40, baseValue: 100) { max(0, $0) }

        let sweeps = SweepStatistics.build(
            meals: [meal], readings: rows, deliveries: [], exercise: [],
            now: fixedNow, calendar: testCalendar
        )

        #expect(sweeps.first?.isInProgress == true)
        #expect(sweeps.first?.points.last?.minute == 40)
        #expect(sweeps.first?.delta == 40)
    }

    @Test("bins carry the p25/p50/p75 of the sweeps that have a point there, with n")
    func binsPercentiles() {
        var allReadings: [SensorGlucose] = []
        var allMeals: [MealEntry] = []
        // Three clean sweeps, +20 / +40 / +90 at t+60.
        for (index, peak) in [20, 40, 90].enumerated() {
            let time = mealTime(daysAgo: index + 2)
            allMeals.append(makeMeal(at: time, carbs: 60))
            allReadings += readings(anchor: time, from: -30, to: 240, baseValue: 100) { minute in
                minute <= 0 ? 0 : min(peak, peak * minute / 60)
            }
        }

        let sweeps = SweepStatistics.build(
            meals: allMeals, readings: allReadings, deliveries: [], exercise: [],
            now: fixedNow, calendar: testCalendar
        )
        #expect(sweeps.filter(\.isClean).count == 3)

        let bins = SweepStatistics.bins(sweeps, cleanOnly: true)
        let atSixty = bins.first(where: { $0.minute == 60 })
        #expect(atSixty?.n == 3)
        #expect(atSixty?.p50 == 40)
        #expect(atSixty?.p25 == 30)
        #expect(atSixty?.p75 == 65)
    }

    @Test("cleanOnly bins drop confounded sweeps; in-progress sweeps never bin at all")
    func binsFiltering() {
        var allReadings: [SensorGlucose] = []
        var allMeals: [MealEntry] = []
        for (index, peak) in [20, 40, 90].enumerated() {
            let time = mealTime(daysAgo: index + 2)
            allMeals.append(makeMeal(at: time, carbs: 60))
            allReadings += readings(anchor: time, from: -30, to: 240, baseValue: 100) { minute in
                minute <= 0 ? 0 : min(peak, peak * minute / 60)
            }
        }
        // A confounded fourth sweep at +200.
        let confoundedTime = mealTime(daysAgo: 6)
        allMeals.append(makeMeal(at: confoundedTime, carbs: 60))
        allReadings += readings(anchor: confoundedTime, from: -30, to: 240, baseValue: 100) { minute in
            minute <= 0 ? 0 : min(200, 200 * minute / 60)
        }
        let correction = InsulinDelivery(
            starts: confoundedTime.addingTimeInterval(minutes(20)),
            ends: confoundedTime.addingTimeInterval(minutes(20)),
            units: 2, type: .correctionBolus
        )
        // An in-progress fifth sweep at +300.
        let liveTime = fixedNow.addingTimeInterval(minutes(-40))
        allMeals.append(makeMeal(at: liveTime, carbs: 60))
        allReadings += readings(anchor: liveTime, from: -30, to: 40, baseValue: 100) { minute in
            minute <= 0 ? 0 : 300
        }

        let sweeps = SweepStatistics.build(
            meals: allMeals, readings: allReadings, deliveries: [correction], exercise: [],
            now: fixedNow, calendar: testCalendar
        )

        let clean = SweepStatistics.bins(sweeps, cleanOnly: true)
        #expect(clean.first(where: { $0.minute == 60 })?.n == 3)
        #expect(clean.first(where: { $0.minute == 60 })?.p50 == 40)

        let all = SweepStatistics.bins(sweeps, cleanOnly: false)
        #expect(all.first(where: { $0.minute == 60 })?.n == 4)
    }

    @Test("carb bucket edges: 15 / 16 / 45 / 46 / 80 / 81, and nil")
    func bucketEdges() {
        #expect(CarbBucket.bucket(forCarbs: 15) == .upTo15)
        #expect(CarbBucket.bucket(forCarbs: 16) == .from16to45)
        #expect(CarbBucket.bucket(forCarbs: 45) == .from16to45)
        #expect(CarbBucket.bucket(forCarbs: 46) == .from46to80)
        #expect(CarbBucket.bucket(forCarbs: 80) == .from46to80)
        #expect(CarbBucket.bucket(forCarbs: 81) == .over80)
        #expect(CarbBucket.bucket(forCarbs: nil) == .unknown)
        #expect(CarbBucket.bucket(forCarbs: 0) == .upTo15)
    }

    @Test("filter narrows by bucket and by clean, independently")
    func filterByBucketAndClean() {
        let sweeps = [
            makeSweep(mealTime: mealTime(daysAgo: 1), carbs: 10),
            makeSweep(mealTime: mealTime(daysAgo: 2), carbs: 60),
            makeSweep(mealTime: mealTime(daysAgo: 3), carbs: 60, isClean: false),
            makeSweep(mealTime: mealTime(daysAgo: 4), carbs: 120)
        ]

        #expect(SweepStatistics.filter(sweeps, bucket: nil, cleanOnly: false).count == 4)
        #expect(SweepStatistics.filter(sweeps, bucket: nil, cleanOnly: true).count == 3)
        #expect(SweepStatistics.filter(sweeps, bucket: .from46to80, cleanOnly: false).count == 2)
        #expect(SweepStatistics.filter(sweeps, bucket: .from46to80, cleanOnly: true).count == 1)
        #expect(SweepStatistics.filter(sweeps, bucket: .upTo15, cleanOnly: false).count == 1)
    }

    @Test("sweeps come back newest first, with their age in days")
    func newestFirstWithAge() {
        var allReadings: [SensorGlucose] = []
        var allMeals: [MealEntry] = []
        for daysAgo in [2, 5, 9] {
            let time = mealTime(daysAgo: daysAgo)
            allMeals.append(makeMeal(at: time, carbs: 60))
            allReadings += readings(anchor: time, from: -30, to: 240, baseValue: 100) { max(0, $0) }
        }

        let sweeps = SweepStatistics.build(
            meals: allMeals, readings: allReadings, deliveries: [], exercise: [],
            now: fixedNow, calendar: testCalendar
        )

        #expect(sweeps.map(\.ageDays) == [2, 5, 9])
    }

    @Test("the y domain is a floor in both directions, in mg/dL")
    func yDomainFloor() {
        #expect(SweepChartMath.yDomainMgdl(deltas: []) == -20...100)
        #expect(SweepChartMath.yDomainMgdl(deltas: [10, 40, 90]) == -20...100)
        #expect(SweepChartMath.yDomainMgdl(deltas: [10, 165]) == -20...180)
        #expect(SweepChartMath.yDomainMgdl(deltas: [-55, 30]) == -60...100)
    }
}

// MARK: - Parity with the shipping meal-overlay math

@Suite("Sweep parity with MealOverlayLogic")
struct SweepParityTests {

    @Test("the sweep's delta matches computeMealOverlayDelta for a completed meal")
    func deltaParity() {
        let time = mealTime(daysAgo: 2)
        let meal = makeMeal(at: time, carbs: 60)
        let rows = readings(anchor: time, from: -30, to: 240, baseValue: 100) { minute in
            minute <= 0 ? 0 : max(0, 60 - abs(minute - 60))
        }

        let shipping = computeMealOverlayDelta(meal: meal, isInProgress: false, sensorGlucoseValues: rows)
        let sweeps = SweepStatistics.build(
            meals: [meal], readings: rows, deliveries: [], exercise: [],
            now: fixedNow, calendar: testCalendar
        )

        #expect(sweeps.first?.delta == shipping.delta)
        // `isLowConfidence` is the same gate the sweep uses for `.insufficientData`.
        #expect(shipping.isLowConfidence == false)
        #expect(sweeps.first?.isClean == true)
    }

    @Test("the sweep's clean verdict matches detectMealConfounders")
    func confounderParity() {
        let time = mealTime(daysAgo: 2)
        let meal = makeMeal(at: time, carbs: 60)
        let rows = readings(anchor: time, from: -30, to: 240, baseValue: 100) { max(0, $0) }
        let correction = InsulinDelivery(
            starts: time.addingTimeInterval(minutes(30)),
            ends: time.addingTimeInterval(minutes(30)),
            units: 2, type: .correctionBolus
        )

        for (deliveries, exercise, others) in [
            ([InsulinDelivery](), [ExerciseEntry](), [MealEntry]()),
            ([correction], [], []),
            ([], [ExerciseEntry(
                startTime: time.addingTimeInterval(minutes(10)),
                endTime: time.addingTimeInterval(minutes(40)),
                activityType: "Running", durationMinutes: 30, activeCalories: nil, source: nil
            )], []),
            ([], [], [makeMeal(at: time.addingTimeInterval(minutes(50)), carbs: 20, name: "Snack")])
        ] {
            let shipping = detectMealConfounders(
                meal: meal,
                insulinDeliveryValues: deliveries,
                exerciseEntryValues: exercise,
                mealEntryValues: [meal] + others
            )
            let sweeps = SweepStatistics.build(
                meals: [meal] + others, readings: rows, deliveries: deliveries, exercise: exercise,
                now: fixedNow, calendar: testCalendar
            )
            let target = sweeps.first(where: { $0.id == meal.id })
            #expect(target?.isClean == shipping.isClean)
        }
    }
}

// MARK: - Twin finder

@Suite("Twin finder")
struct TwinFinderTests {

    private func subject() -> MealSweep {
        makeSweep(mealTime: mealTime(daysAgo: 0), carbs: 80, minutesOfDay: 19 * 60, ageDays: 0, delta: 47, peakMinutes: 38)
    }

    @Test("twins sit within ±25 % of the carbs and in the same bucket")
    func carbTolerance() {
        let me = subject()
        let pool = [
            makeSweep(mealTime: mealTime(daysAgo: 1), carbs: 80, minutesOfDay: 19 * 60),   // exact
            makeSweep(mealTime: mealTime(daysAgo: 2), carbs: 61, minutesOfDay: 19 * 60),   // 80 * 0.75 = 60 → in
            makeSweep(mealTime: mealTime(daysAgo: 3), carbs: 59, minutesOfDay: 19 * 60),   // out (< 60)
            makeSweep(mealTime: mealTime(daysAgo: 4), carbs: 120, minutesOfDay: 19 * 60)   // out (> 100 and another bucket)
        ]

        let twins = TwinFinder.twins(for: me, in: pool)
        #expect(twins.count == 2)
        #expect(twins.allSatisfy { ($0.carbs ?? 0) >= 60 })
    }

    @Test("twins sit within ±90 minutes of the same time of day, wrapping at midnight")
    func timeOfDayTolerance() {
        let me = makeSweep(mealTime: mealTime(daysAgo: 0), carbs: 80, minutesOfDay: 30, ageDays: 0)
        let pool = [
            makeSweep(mealTime: mealTime(daysAgo: 1), carbs: 80, minutesOfDay: 23 * 60 + 30), // 60 min earlier, wraps
            makeSweep(mealTime: mealTime(daysAgo: 2), carbs: 80, minutesOfDay: 2 * 60),       // 90 min later → in
            makeSweep(mealTime: mealTime(daysAgo: 3), carbs: 80, minutesOfDay: 3 * 60)        // 150 min later → out
        ]

        let twins = TwinFinder.twins(for: me, in: pool)
        #expect(twins.count == 2)
    }

    @Test("twins exclude the meal itself, confounded sweeps, and in-progress sweeps")
    func exclusions() {
        let me = subject()
        let pool = [
            me,
            makeSweep(mealTime: mealTime(daysAgo: 1), carbs: 80, minutesOfDay: 19 * 60, isClean: false),
            makeSweep(mealTime: mealTime(daysAgo: 2), carbs: 80, minutesOfDay: 19 * 60, isInProgress: true),
            makeSweep(mealTime: mealTime(daysAgo: 3), carbs: 80, minutesOfDay: 19 * 60)
        ]

        let twins = TwinFinder.twins(for: me, in: pool)
        #expect(twins.count == 1)
        #expect(twins.first?.ageDays == 1)
    }

    @Test("at most five twins, newest first")
    func capAndOrder() {
        let me = subject()
        let pool = (1...8).map { day in
            makeSweep(mealTime: mealTime(daysAgo: day), carbs: 80, minutesOfDay: 19 * 60, ageDays: day)
        }

        let twins = TwinFinder.twins(for: me, in: pool)
        #expect(twins.count == 5)
        #expect(twins.map(\.ageDays) == [1, 2, 3, 4, 5])
    }

    @Test("a meal with no carbs has no twins")
    func noCarbsNoTwins() {
        let me = makeSweep(mealTime: mealTime(daysAgo: 0), carbs: nil, minutesOfDay: 19 * 60)
        let pool = [makeSweep(mealTime: mealTime(daysAgo: 1), carbs: nil, minutesOfDay: 19 * 60)]
        #expect(TwinFinder.twins(for: me, in: pool).isEmpty)
    }

    @Test("summary is nil under three twins, and medians them above it")
    func summaryGate() {
        let two = [
            makeSweep(mealTime: mealTime(daysAgo: 1), carbs: 80, delta: 40, peakMinutes: 50),
            makeSweep(mealTime: mealTime(daysAgo: 2), carbs: 80, delta: 42, peakMinutes: 60)
        ]
        #expect(TwinFinder.summary(of: two) == nil)

        let four = two + [
            makeSweep(mealTime: mealTime(daysAgo: 3), carbs: 80, delta: 30, peakMinutes: 40),
            makeSweep(mealTime: mealTime(daysAgo: 4), carbs: 80, delta: 52, peakMinutes: 70)
        ]
        let summary = TwinFinder.summary(of: four)
        #expect(summary?.n == 4)
        #expect(summary?.medianDelta == 41)
        #expect(summary?.medianPeakMinutes == 55)
    }
}

// MARK: - LAPS line

@Suite("Sweep LAPS card")
struct SweepLapsFormatterTests {

    @Test("the LAPS line renders the artboard string")
    func artboardLine() {
        let subject = makeSweep(
            mealTime: fixedNow.addingTimeInterval(minutes(-38)),
            carbs: 80, minutesOfDay: 19 * 60, ageDays: 0,
            isInProgress: true, delta: 47, peakMinutes: 38
        )
        let twins = TwinSummary(medianDelta: 41, medianPeakMinutes: 55, n: 4)

        #expect(SweepLapsFormatter.title(for: subject) == "LAPS · 80g DINNER")
        #expect(
            SweepLapsFormatter.line(
                subject: subject, twins: twins, glucoseUnit: .mgdL,
                now: fixedNow, calendar: testCalendar
            ) == "TODAY +47 (38 MIN) · TWINS MEDIAN +41 · PEAK 55 MIN (n=4)"
        )
    }

    @Test("under three twins the line teaches instead of comparing")
    func notEnoughTwins() {
        let subject = makeSweep(
            mealTime: fixedNow.addingTimeInterval(minutes(-38)),
            carbs: 80, minutesOfDay: 19 * 60, ageDays: 0,
            isInProgress: true, delta: 47, peakMinutes: 38
        )

        #expect(
            SweepLapsFormatter.line(
                subject: subject, twins: nil, glucoseUnit: .mgdL,
                now: fixedNow, calendar: testCalendar
            ) == "TODAY +47 (38 MIN) · TWINS n<3 · KEEP LOGGING"
        )
    }

    @Test("an older subject is labelled by its age, not by a locale-dependent date")
    func olderSubject() {
        let subject = makeSweep(
            mealTime: mealTime(daysAgo: 2), carbs: 80, minutesOfDay: 19 * 60, ageDays: 2,
            delta: 30, peakMinutes: 45
        )
        let line = SweepLapsFormatter.line(
            subject: subject, twins: nil, glucoseUnit: .mgdL,
            now: fixedNow, calendar: testCalendar
        )
        #expect(line.hasPrefix("2D AGO +30 (45 MIN)"))
    }

    @Test("mmol/L converts the deltas rather than printing mg/dL numbers")
    func mmolConversion() {
        let subject = makeSweep(
            mealTime: fixedNow.addingTimeInterval(minutes(-38)),
            carbs: 80, minutesOfDay: 19 * 60, ageDays: 0,
            isInProgress: true, delta: 47, peakMinutes: 38
        )
        let line = SweepLapsFormatter.line(
            subject: subject, twins: TwinSummary(medianDelta: 41, medianPeakMinutes: 55, n: 4),
            glucoseUnit: .mmolL, now: fixedNow, calendar: testCalendar
        )
        #expect(!line.contains("+47"))
        #expect(!line.contains("+41"))
        #expect(line.contains("(38 MIN)"))
        #expect(line.contains("(n=4)"))
    }

    @Test("a sweep with no resolved delta says so rather than inventing one")
    func noDelta() {
        let subject = makeSweep(
            mealTime: fixedNow.addingTimeInterval(minutes(-38)),
            carbs: 80, minutesOfDay: 19 * 60, ageDays: 0,
            isInProgress: true, delta: nil, peakMinutes: nil
        )
        let line = SweepLapsFormatter.line(
            subject: subject, twins: nil, glucoseUnit: .mgdL,
            now: fixedNow, calendar: testCalendar
        )
        #expect(line.hasPrefix("TODAY —"))
    }

    @Test("a nameless meal still gets a title")
    func namelessTitle() {
        let subject = makeSweep(mealTime: fixedNow, carbs: nil, name: "")
        #expect(SweepLapsFormatter.title(for: subject) == "LAPS · MEAL")
    }
}

// MARK: - Lab sweep state + read cap

@Suite("Lab sweep evidence")
struct LabSweepEvidenceTests {

    @Test("labSweeps is nil on a fresh state and round-trips through the reducer")
    func reducerSetAndClear() {
        var state: DirectState = makeState()
        #expect(state.labSweeps == nil)

        let evidence = LabSweepEvidence(days: 30, sweeps: [], loadedAt: fixedNow)
        reduce(&state, .setLabSweeps(evidence: evidence))
        #expect(state.labSweeps?.days == 30)
        #expect(state.labSweeps?.sweeps.isEmpty == true)

        reduce(&state, .setLabSweeps(evidence: nil))
        #expect(state.labSweeps == nil)
    }

    @Test("the sweep read is capped at 90 days — the ALL chip does not read 9999")
    func daysCap() {
        #expect(LabSweepStore.effectiveDays(7) == 7)
        #expect(LabSweepStore.effectiveDays(30) == 30)
        #expect(LabSweepStore.effectiveDays(90) == 90)
        #expect(LabSweepStore.effectiveDays(9999) == 90)
        #expect(LabSweepStore.effectiveDays(0) == 1)
        #expect(LabSweepStore.effectiveDays(-5) == 1)
    }

    @Test("the drawn-sweep cap keeps the newest 120")
    func drawCap() {
        let sweeps = (1...200).map { day in
            makeSweep(mealTime: mealTime(daysAgo: day), carbs: 60, ageDays: day)
        }
        let drawn = SweepStatistics.capped(sweeps)
        #expect(drawn.count == SweepStatistics.maxDrawnSweeps)
        #expect(drawn.first?.ageDays == 1)
        #expect(drawn.last?.ageDays == SweepStatistics.maxDrawnSweeps)
    }
}

// MARK: - Sweep chart + LAPS view helpers

@Suite("Sweep view helpers")
struct SweepViewHelperTests {

    @Test("the LAPS subject is the newest sweep that actually has a trace")
    func lapsSubject() {
        let drawable = makeSweep(
            mealTime: mealTime(daysAgo: 1), carbs: 60,
            points: [SweepPoint(minute: 0, delta: 0), SweepPoint(minute: 5, delta: 12)]
        )
        let justLogged = makeSweep(mealTime: mealTime(daysAgo: 0), carbs: 60, points: [])

        // A meal logged seconds ago has no readings yet — it must not blank the card.
        #expect(SweepStatistics.lapsSubject([justLogged, drawable])?.id == drawable.id)
        #expect(SweepStatistics.lapsSubject([justLogged])?.id == justLogged.id)
        #expect(SweepStatistics.lapsSubject([]) == nil)
    }

    @Test("a twin row states its age, size, response and why it qualified")
    func twinRow() {
        let twin = makeSweep(
            mealTime: mealTime(daysAgo: 3), carbs: 78, ageDays: 3,
            delta: 38, peakMinutes: 52
        )
        #expect(
            SweepLapsFormatter.twinRow(twin, glucoseUnit: .mgdL) == "3D AGO · 78g · +38 (52 MIN) · CLEAN"
        )
    }

    @Test("the y axis ticks span the domain without crowding the plot")
    func yTicks() {
        #expect(SweepChartMath.yTicksMgdl(domain: -20...100) == [-20, 0, 20, 40, 60, 80, 100])
        // A wide domain steps coarser rather than printing fifteen labels.
        let wide = SweepChartMath.yTicksMgdl(domain: -60...240)
        #expect(wide.count <= 8)
        #expect(wide.first == -60)
        #expect(wide.contains(0))
    }
}
