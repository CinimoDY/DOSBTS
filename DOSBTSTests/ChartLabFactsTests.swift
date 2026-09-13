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

// MARK: - Lab figures

@Suite("Lab figures and captions")
struct LabFigureTests {
    // A `LabFigure` cannot be constructed without its `n`: the only initializer
    // requires it and there is no default. That is a COMPILE-TIME guarantee —
    // `LabFigure(kind: .delta, value: 42, unit: "mg/dL")` does not compile, so it
    // cannot be written as a runtime expectation here. `rule_everyFigureShipsWithN`
    // below is the source-scan that keeps it that way.

    private func figure(
        _ kind: LabFigure.Kind,
        _ value: Double,
        unit: String = "",
        n: Int = 1,
        label: String? = nil,
        spread: ClosedRange<Double>? = nil,
        citesSampleSize: Bool = false
    ) -> LabFigure {
        LabFigure(kind: kind, value: value, unit: unit, n: n, spread: spread, label: label, citesSampleSize: citesSampleSize)
    }

    @Test("a derived figure prints its sample size last")
    func citesSampleSize() {
        let delta = figure(.delta, 42, unit: "mg/dL", n: 7, citesSampleSize: true)
        #expect(LabCaption.text(for: delta, unit: .mgdL) == "+42 mg/dL · n=7")
    }

    @Test("glucose values convert to the display unit, they are never reprinted raw")
    func convertsToDisplayUnit() {
        let glucose = figure(.glucose, 75.6, unit: "mg/dL", n: 7, citesSampleSize: true)
        let expected = GlucoseFormatters.mmolLFormatter.string(from: 75.6.toMmolL() as NSNumber) ?? ""

        #expect(expected.isEmpty == false)
        #expect(LabCaption.text(for: glucose, unit: .mmolL) == "\(expected) mmol/L · n=7")
        #expect(LabCaption.text(for: glucose, unit: .mgdL) == "76 mg/dL · n=7")
    }

    @Test("an empty unit prints the bare number — the chart's own axis carries the unit")
    func emptyUnitPrintsBareNumber() {
        #expect(LabCaption.text(for: figure(.glucose, 62, n: 11, label: "T-0"), unit: .mgdL) == "T-0 62")
    }

    @Test("insulin and carbs suffix their unit without a space, like the hero does")
    func tightUnits() {
        #expect(LabCaption.text(for: figure(.iob, 1.8, unit: "U", label: "IOB"), unit: .mgdL) == "IOB 1.8U")
        #expect(LabCaption.text(for: figure(.insulin, 7, unit: "U", label: "LAST BOLUS T-4h10"), unit: .mgdL)
            == "LAST BOLUS T-4h10 7.0U")
        #expect(LabCaption.text(for: figure(.carbs, 60, unit: "g", label: "LUNCH"), unit: .mgdL) == "LUNCH 60g")
    }

    @Test("a word unit keeps its space")
    func wordUnits() {
        #expect(LabCaption.text(for: figure(.peakMinutes, 50, unit: "MIN", n: 24, label: "PEAK"), unit: .mgdL)
            == "PEAK 50 MIN")
        #expect(LabCaption.text(for: figure(.count, 6, unit: "SIMILAR MEALS", n: 6, label: "1 OF"), unit: .mgdL)
            == "1 OF 6 SIMILAR MEALS")
    }

    @Test("n=0 renders an em dash, so an absent number can never read as a zero")
    func zeroSampleSizeIsADash() {
        #expect(LabCaption.text(for: figure(.cob, 0, unit: "g", n: 0, label: "COB"), unit: .mgdL) == "COB —")
        #expect(LabCaption.text(for: figure(.glucose, 0, n: 0), unit: .mgdL) == "—")
    }

    @Test("the sample-size figure IS the n, so it prints even at zero")
    func sampleCountPrintsZero() {
        #expect(LabCaption.text(for: figure(.sampleCount, 24, unit: "RDG", n: 24), unit: .mgdL) == "n=24 RDG")
        #expect(LabCaption.text(for: figure(.sampleCount, 0, unit: "RDG", n: 0), unit: .mgdL) == "n=0 RDG")
    }

    @Test("a spread prints beside its figure, in the display unit")
    func spreadPrints() {
        let median = figure(.median, 138, n: 288, label: "MEDIAN", spread: 112 ... 190)
        #expect(LabCaption.text(for: median, unit: .mgdL) == "MEDIAN 138 (112–190)")
    }

    @Test("a band prints its range, converted")
    func bandPrints() {
        let band = figure(.band, 100, n: 24, label: "BAND", spread: 80 ... 120)
        #expect(LabCaption.text(for: band, unit: .mgdL) == "BAND 80–120")
    }

    @Test("observations restate a record: label only, label + value, or a dash at n=0")
    func observations() {
        #expect(LabCaption.text(for: .observation(label: "CLEAN", value: nil, n: 1), unit: .mgdL) == "CLEAN")
        #expect(LabCaption.text(for: .observation(label: "HR", value: "71→96", n: 12), unit: .mgdL) == "HR 71→96")
        #expect(LabCaption.text(for: .observation(label: "TAG", value: nil, n: 0), unit: .mgdL) == "TAG —")
        #expect(LabCaption.text(for: .observation(label: "TAG", value: "SICK", n: 0), unit: .mgdL) == "TAG —")
    }

    @Test("a line joins its items with the DOS separator")
    func joinsLines() {
        let items: [LabFactItem] = [
            .figure(figure(.glucose, 62, n: 11, label: "T-0")),
            .figure(figure(.iob, 1.8, unit: "U", label: "IOB")),
            .figure(figure(.cob, 0, unit: "g", n: 0, label: "COB"))
        ]
        #expect(LabCaption.text(for: items, unit: .mgdL) == "T-0 62 · IOB 1.8U · COB —")
    }
}

// MARK: - Chart highlights

@Suite("Chart highlights")
struct ChartHighlightsTests {
    // MARK: Fixtures

    private func bolus(_ minutes: Int, _ units: Double, _ type: InsulinType = .mealBolus) -> InsulinDelivery {
        InsulinDelivery(starts: at(minutes), ends: at(minutes), units: units, type: type)
    }

    private func meal(_ minutes: Int, _ carbs: Double, _ description: String = "LUNCH") -> MealEntry {
        MealEntry(timestamp: at(minutes), mealDescription: description, carbsGrams: carbs)
    }

    private func exercise(_ minutes: Int, _ durationMinutes: Double, _ type: String = "RUN") -> ExerciseEntry {
        ExerciseEntry(
            startTime: at(minutes),
            endTime: at(minutes + Int(durationMinutes)),
            activityType: type,
            durationMinutes: durationMinutes,
            activeCalories: nil,
            source: nil
        )
    }

    /// A hypo at minute 0, a 7 U bolus 4 h 10 min before it, a 30-minute run
    /// 9 h before it, heart rate around the onset and a SICK note in the evening.
    private var hypoFixture: (
        readings: [SensorGlucose],
        deliveries: [InsulinDelivery],
        exercise: [ExerciseEntry],
        heartRate: [HeartRateSample],
        notes: [JournalNote],
        iob: [LabOnsetIOB]
    ) {
        (
            readings: run(from: -120, to: -5, value: 140) + run(from: 0, to: 50, value: 62) + run(from: 55, to: 120, value: 110),
            deliveries: [bolus(-250, 7)],
            exercise: [exercise(-540, 30)],
            heartRate: [HeartRateSample(time: at(-20), bpm: 71), HeartRateSample(time: at(20), bpm: 96)],
            notes: [JournalNote(timestamp: at(-60), text: "family's sick", tag: .sick)],
            iob: [LabOnsetIOB(date: at(0), units: 1.8, coverage: .full)]
        )
    }

    private func hypoFacts() -> [ChartFact] {
        let fixture = hypoFixture
        return ChartHighlights.facts(
            readings: fixture.readings,
            deliveries: fixture.deliveries,
            meals: [],
            exercise: fixture.exercise,
            notes: fixture.notes,
            iob: fixture.iob,
            heartRate: fixture.heartRate,
            windowStart: at(-120),
            now: at(180)
        )
    }

    // MARK: Hypo onset

    @Test("a hypo is the first fact, and it is the Black Box")
    func hypoRanksFirst() {
        let facts = hypoFacts()
        #expect(facts.first?.kind == .hypoOnset)
        #expect(facts.first?.severity == 3)
        #expect(facts.first?.anchor == at(0))
        #expect(facts.first?.end == at(50))
    }

    @Test("the Black Box title names the onset and the duration")
    func hypoTitle() {
        guard let fact = hypoFacts().first else { return #expect(Bool(false), "no fact") }
        #expect(LabCaption.text(for: fact.title, unit: .mgdL)
            == "BLACK BOX · HYPO \(at(0).toLocalTime()) · 50 MIN")
    }

    @Test("T-0 is the onset reading itself, carrying the episode's sample size")
    func hypoTZero() {
        guard let fact = hypoFacts().first, let first = fact.lines.first else {
            return #expect(Bool(false), "no fact")
        }
        let figures = first.compactMap { item -> LabFigure? in
            if case .figure(let figure) = item { return figure }
            return nil
        }
        #expect(figures.first?.value == 62)
        // 11 readings at 5-minute spacing across the 50-minute episode.
        #expect(figures.first?.n == 11)
        #expect(LabCaption.text(for: first, unit: .mgdL) == "T-0 62 · IOB 1.8U · COB — · n=11 RDG")
    }

    @Test("the Black Box states what was already on board and what came before")
    func hypoContextLines() {
        guard let fact = hypoFacts().first, fact.lines.count >= 3 else {
            return #expect(Bool(false), "no fact")
        }
        #expect(LabCaption.text(for: fact.lines[1], unit: .mgdL)
            == "LAST BOLUS T-4h10 7.0U · EXERCISE T-9h 30m RUN")
        #expect(LabCaption.text(for: fact.lines[2], unit: .mgdL) == "HR 71→96 · TAG SICK")
    }

    @Test("missing context is an em dash — but only when the window covers the lookback")
    func hypoMissingContext() {
        let facts = ChartHighlights.facts(
            readings: run(from: -60, to: -5, value: 140) + run(from: 0, to: 50, value: 62),
            deliveries: [],
            meals: [],
            exercise: [],
            notes: [],
            iob: [],
            heartRate: [],
            // 25 hours of loaded history behind the onset: every lookback fits,
            // so "nothing found" really does mean "nothing happened".
            windowStart: at(-1500),
            now: at(180)
        )
        guard let fact = facts.first, fact.lines.count >= 3 else {
            return #expect(Bool(false), "no fact")
        }
        #expect(LabCaption.text(for: fact.lines[0], unit: .mgdL) == "T-0 62 · IOB — · COB — · n=11 RDG")
        #expect(LabCaption.text(for: fact.lines[1], unit: .mgdL) == "LAST BOLUS — · EXERCISE —")
        #expect(LabCaption.text(for: fact.lines[2], unit: .mgdL) == "HR — · TAG —")
    }

    @Test("an episode already under way at the window start is not a Black Box")
    func hypoOpenAtWindowStart() {
        // The first loaded reading IS the first low: on a picked day this is a
        // hypo that began before midnight, and every T-offset from it would be
        // measured from the day boundary rather than from an event.
        let facts = ChartHighlights.facts(
            readings: run(from: 0, to: 50, value: 62) + run(from: 55, to: 120, value: 110),
            deliveries: [bolus(-250, 7)],
            meals: [],
            exercise: [],
            notes: [],
            iob: [],
            heartRate: [],
            windowStart: at(0),
            now: at(180)
        )
        guard let fact = facts.first(where: { $0.kind == .hypoOnset }) else {
            return #expect(Bool(false), "no hypo fact")
        }

        let title = LabCaption.text(for: fact.title, unit: .mgdL)
        #expect(title == "HYPO \(at(0).toLocalTime()) · OPEN AT \(at(0).toLocalTime()) · 50 MIN")
        #expect(title.contains("BLACK BOX") == false)

        let rendered = fact.lines.map { LabCaption.text(for: $0, unit: .mgdL) }
        #expect(rendered == ["LOW 62 · n=11 RDG"])
        #expect(rendered.contains { $0.contains("T-0") } == false)
        #expect(rendered.contains { $0.contains("T-") } == false)
    }

    @Test("a short window names the hours it can speak for instead of claiming nothing happened")
    func hypoNamesCoveredHours() {
        let facts = ChartHighlights.facts(
            readings: run(from: -120, to: -5, value: 140) + run(from: 0, to: 50, value: 62),
            deliveries: [],
            meals: [],
            exercise: [],
            notes: [],
            iob: [],
            heartRate: [],
            // Only two hours of history behind the onset — a 22:00 bolus would
            // simply not be loaded, so `—` would be a lie.
            windowStart: at(-120),
            now: at(180)
        )
        guard let fact = facts.first, fact.lines.count >= 3 else {
            return #expect(Bool(false), "no fact")
        }
        #expect(LabCaption.text(for: fact.lines[1], unit: .mgdL) == "LAST BOLUS NONE IN 2H · EXERCISE NONE IN 2H")
        // Heart rate only ever looks 30 minutes back, which two hours DOES cover,
        // so its absence is real and still reads as an em dash.
        #expect(LabCaption.text(for: fact.lines[2], unit: .mgdL) == "HR — · TAG NONE IN 2H")
    }

    @Test("IOB says which half it can account for")
    func hypoBolusOnlyIOB() {
        let facts = ChartHighlights.facts(
            readings: run(from: -60, to: -5, value: 140) + run(from: 0, to: 50, value: 62),
            deliveries: [],
            meals: [],
            exercise: [],
            notes: [],
            iob: [LabOnsetIOB(date: at(0), units: 0.4, coverage: .bolusOnly)],
            heartRate: [],
            windowStart: at(-1500),
            now: at(180)
        )
        guard let fact = facts.first, let first = fact.lines.first else {
            return #expect(Bool(false), "no fact")
        }
        #expect(LabCaption.text(for: first, unit: .mgdL) == "T-0 62 · BOLUS IOB 0.4U · COB — · n=11 RDG")
    }

    @Test("the episode sample size counts the lows, not the in-range readings across the span")
    func hypoSampleSizeCountsLows() {
        // Lows 0–20 and 40–60 with a 15-minute return to range between them: one
        // episode (the gap is under the 30-minute separation), but only ten of
        // the thirteen readings across that span were ever low.
        let facts = ChartHighlights.facts(
            readings: run(from: -60, to: -5, value: 140)
                + run(from: 0, to: 20, value: 62)
                + run(from: 25, to: 35, value: 120)
                + run(from: 40, to: 60, value: 64),
            deliveries: [],
            meals: [],
            exercise: [],
            notes: [],
            iob: [],
            heartRate: [],
            windowStart: at(-1500),
            now: at(180)
        )
        guard let fact = facts.first, let first = fact.lines.first else {
            return #expect(Bool(false), "no fact")
        }
        #expect(LabCaption.text(for: fact.title, unit: .mgdL).hasSuffix("· 60 MIN"))
        #expect(LabCaption.text(for: first, unit: .mgdL).hasSuffix("· n=10 RDG"))
    }

    // MARK: Meal response

    @Test("a 60 g meal that peaks +54 is a meal fact with its peak and its readings")
    func mealResponse() {
        let readings = run(from: -15, to: -5, value: 100)
            + run(from: 0, to: 45, value: 120)
            + [reading(50, 154)]
            + run(from: 55, to: 120, value: 130)
        let facts = ChartHighlights.facts(
            readings: readings,
            deliveries: [bolus(0, 6)],
            meals: [meal(0, 60)],
            exercise: [],
            notes: [],
            iob: [],
            heartRate: [],
            now: at(180)
        )

        guard let fact = facts.first(where: { $0.kind == .mealResponse }) else {
            return #expect(Bool(false), "no meal fact")
        }
        #expect(fact.anchor == at(0))
        #expect(LabCaption.text(for: fact.title, unit: .mgdL) == "LUNCH 60g · +54 · PEAK 50 MIN")

        let line = LabCaption.text(for: fact.lines[0], unit: .mgdL)
        #expect(line.hasPrefix("1 OF 1 SIMILAR MEALS · CLEAN · n="))
        #expect(line.hasSuffix(" RDG"))
    }

    @Test("a meal whose two-hour window has not closed yet states nothing")
    func mealWindowNotClosed() {
        let facts = ChartHighlights.facts(
            readings: run(from: -15, to: 30, value: 120),
            deliveries: [],
            meals: [meal(0, 60)],
            exercise: [],
            notes: [],
            iob: [],
            heartRate: [],
            now: at(30)
        )
        #expect(facts.contains { $0.kind == .mealResponse } == false)
    }

    @Test("a correction bolus in the window makes the meal confounded, not clean")
    func mealConfounded() {
        let readings = run(from: -15, to: 120, value: 120)
        let facts = ChartHighlights.facts(
            readings: readings,
            deliveries: [bolus(30, 2, .correctionBolus)],
            meals: [meal(0, 60)],
            exercise: [],
            notes: [],
            iob: [],
            heartRate: [],
            now: at(180)
        )
        guard let fact = facts.first(where: { $0.kind == .mealResponse }) else {
            return #expect(Bool(false), "no meal fact")
        }
        #expect(LabCaption.text(for: fact.lines[0], unit: .mgdL).contains("CONFOUNDED"))
    }

    @Test("a meal with no carbs logged is comparable to nothing")
    func mealWithoutCarbs() {
        let readings = run(from: -15, to: 120, value: 120)
        let facts = ChartHighlights.facts(
            readings: readings,
            deliveries: [],
            meals: [
                MealEntry(timestamp: at(0), mealDescription: "SOUP", carbsGrams: nil),
                meal(240, 10, "SNACK")
            ],
            exercise: [],
            notes: [],
            iob: [],
            heartRate: [],
            now: at(400)
        )
        guard let fact = facts.first(where: { $0.id.hasPrefix("meal-") }) else {
            return #expect(Bool(false), "no meal fact")
        }
        // Not "1 OF 2 SIMILAR MEALS": a missing carb count is not zero carbs.
        #expect(LabCaption.text(for: fact.lines[0], unit: .mgdL).hasPrefix("SIMILAR MEALS — · "))
    }

    // MARK: Stacked bolus

    @Test("two boluses inside the stacking window are one stacked-bolus fact")
    func stackedBolus() {
        let facts = ChartHighlights.facts(
            readings: run(from: 0, to: 240, value: 150),
            deliveries: [bolus(0, 5), bolus(90, 3, .correctionBolus)],
            meals: [],
            exercise: [],
            notes: [],
            iob: [],
            heartRate: [],
            now: at(300)
        )
        guard let fact = facts.first(where: { $0.kind == .stackedBolus }) else {
            return #expect(Bool(false), "no stacked-bolus fact")
        }
        #expect(fact.severity == 2)
        #expect(fact.anchor == at(90))
        #expect(LabCaption.text(for: fact.title, unit: .mgdL) == "STACKED BOLUS · 90 MIN APART")
        #expect(LabCaption.text(for: fact.lines[0], unit: .mgdL) == "FIRST 5.0U · THEN 3.0U")
    }

    @Test("a meal bolus after a meal bolus is lunch, not stacking")
    func mealBolusIsNotStacking() {
        let facts = ChartHighlights.facts(
            readings: run(from: 0, to: 240, value: 150),
            deliveries: [bolus(0, 5), bolus(90, 4)],
            meals: [],
            exercise: [],
            notes: [],
            iob: [],
            heartRate: [],
            now: at(300)
        )
        #expect(facts.contains { $0.kind == .stackedBolus } == false)
    }

    @Test("boluses further apart than the stacking window are not stacked")
    func notStacked() {
        let facts = ChartHighlights.facts(
            readings: run(from: 0, to: 600, value: 150),
            deliveries: [bolus(0, 5), bolus(300, 3)],
            meals: [],
            exercise: [],
            notes: [],
            iob: [],
            heartRate: [],
            now: at(700)
        )
        #expect(facts.contains { $0.kind == .stackedBolus } == false)
    }

    // MARK: Ranking

    @Test("facts rank by severity, then by recency, and stop at five")
    func rankingAndCap() {
        var readings = run(from: -15, to: -5, value: 100)
        var meals: [MealEntry] = []
        for index in 0 ..< 7 {
            let start = index * 180
            readings += run(from: start, to: start + 120, value: 120 + index)
            meals.append(meal(start, 60, "MEAL \(index)"))
        }
        readings += run(from: 1500, to: 1550, value: 62) // a hypo, last in time

        let facts = ChartHighlights.facts(
            readings: readings,
            deliveries: [],
            meals: meals,
            exercise: [],
            notes: [],
            iob: [],
            heartRate: [],
            now: at(2000)
        )

        #expect(facts.count == ChartHighlights.maxFacts)
        #expect(facts.first?.kind == .hypoOnset)
        // Within one severity, newest first.
        let mealAnchors = facts.filter { $0.kind == .mealResponse }.map(\.anchor)
        #expect(mealAnchors == mealAnchors.sorted(by: >))
    }

    @Test("ids are stable across calls, so a card can be tapped twice")
    func stableIds() {
        let first = hypoFacts().map(\.id)
        let second = hypoFacts().map(\.id)
        #expect(first == second)
        #expect(first.first?.hasPrefix("hypo-") == true)
    }

    // MARK: Feature sheet

    @Test("the sheet counts what the window actually holds")
    func sheetCounts() {
        let readings = run(from: 0, to: 240, value: 120) + run(from: 250, to: 300, value: 62)
        let meals = [meal(30, 60, "BREAKFAST"), meal(200, 40, "LUNCH")]
        let sheet = ChartHighlights.sheet(
            readings: readings,
            meals: meals,
            deliveries: [bolus(210, 2, .correctionBolus)],
            exercise: [],
            notes: [JournalNote(timestamp: at(10), text: "slept badly", tag: .sluggish)],
            window: DateInterval(start: at(0), end: at(300))
        )

        #expect(sheet.readings == readings.count)
        #expect(sheet.hypoEpisodes == 1)
        #expect(sheet.meals == 2)
        #expect(sheet.cleanMeals == 1) // the correction bolus confounds the second meal
        #expect(sheet.notes == 1)

        let line = LabCaption.text(for: sheet.items(), unit: .mgdL)
        #expect(line.hasPrefix("5H · n=\(readings.count) · MEDIAN "))
        #expect(line.contains("· 1 HYPO · 2 MEALS · 1 CLEAN"))
    }

    @Test("an empty window still states its own emptiness")
    func emptySheet() {
        let sheet = ChartHighlights.sheet(
            readings: [],
            meals: [],
            deliveries: [],
            exercise: [],
            notes: [],
            window: DateInterval(start: at(0), end: at(60))
        )
        #expect(sheet.readings == 0)
        #expect(LabCaption.text(for: sheet.items(), unit: .mgdL) == "1H · n=0 · MEDIAN — · P95 — · 0 HYPO · 0 MEALS · 0 CLEAN")
    }
}

// MARK: - Fact pins

@Suite("Fact pins")
struct LabFactPinTests {
    private func fact(_ minutes: Int, severity: Int = 1) -> ChartFact {
        ChartFact(
            id: "fact-\(minutes)",
            kind: .mealResponse,
            anchor: at(minutes),
            end: nil,
            title: [.observation(label: "MEAL", value: nil, n: 1)],
            lines: [],
            severity: severity
        )
    }

    @Test("pins are numbered in the order the facts are ranked, not in time order")
    func numbersFollowRanking() {
        let pins = LabFactPins.layout([fact(600), fact(0), fact(300)])
        #expect(pins.map(\.index) == [1, 2, 3])
        #expect(pins.map(\.fact.anchor) == [at(600), at(0), at(300)])
    }

    @Test("pins far apart are not nudged")
    func noShiftWhenSpread() {
        let pins = LabFactPins.layout([fact(0), fact(60), fact(120)])
        #expect(pins.allSatisfy { $0.labelShift == 0 })
    }

    @Test("two pins inside the crowding window are nudged apart, symmetrically")
    func shiftsWhenCrowded() {
        let pins = LabFactPins.layout([fact(0), fact(10)])
        let shifts = pins.sorted { $0.fact.anchor < $1.fact.anchor }.map(\.labelShift)
        #expect(shifts == [-LabFactPins.shiftStep / 2, LabFactPins.shiftStep / 2])
    }

    @Test("a crowd of three spreads around its centre")
    func shiftsThree() {
        let pins = LabFactPins.layout([fact(0), fact(5), fact(10)])
        let shifts = pins.sorted { $0.fact.anchor < $1.fact.anchor }.map(\.labelShift)
        #expect(shifts == [-LabFactPins.shiftStep, 0, LabFactPins.shiftStep])
    }

    @Test("a hypo pin is red, everything else amber")
    func hypoPinIsRed() {
        let hypo = ChartFact(
            id: "hypo-x",
            kind: .hypoOnset,
            anchor: at(0),
            end: at(50),
            title: [],
            lines: [],
            severity: 3
        )
        #expect(LabFactPins.isOnsetRule(hypo))
        #expect(LabFactPins.isOnsetRule(fact(0)) == false)
    }
}

// MARK: - Placing a cursor from a card

@Suite("Lab cursor placement")
struct LabCursorPlacementTests {
    @Test("placing a cursor replaces whatever was standing")
    func placeReplaces() {
        var cursors = LabCursorState()
        cursors.apply(selection: at(0), minRange: 300)
        cursors.apply(selection: nil, minRange: 300)
        cursors.apply(selection: at(60), minRange: 300) // promotes to a range
        cursors.apply(selection: nil, minRange: 300)
        #expect(cursors.range != nil)

        cursors.place(at: at(120))
        #expect(cursors.range == nil)
        #expect(cursors.cursor == at(120))
    }

    @Test("a press after a placed cursor still measures from it")
    func placedCursorMeasures() {
        var cursors = LabCursorState()
        cursors.place(at: at(0))
        cursors.apply(selection: at(60), minRange: 300)
        cursors.apply(selection: nil, minRange: 300)
        #expect(cursors.range == at(0) ... at(60))
    }
}

// MARK: - Accessibility summary

@Suite("Lab chart accessibility")
struct LabChartAccessibilityTests {
    private func sheet(readings: Int) -> ChartFeatureSheet {
        ChartHighlights.sheet(
            readings: run(from: 0, to: (readings - 1) * 5, value: 120),
            meals: [],
            deliveries: [],
            exercise: [],
            notes: [],
            window: DateInterval(start: at(0), end: at(24 * 60))
        )
    }

    @Test("the chart announces the feature sheet, then how many facts it cites")
    func summaryReadsTheSheet() {
        let summary = LabChartAccessibility.summary(sheet: sheet(readings: 5), facts: [], unit: .mgdL)
        #expect(summary.hasPrefix("Lab chart. 24H · n=5 · MEDIAN 120"))
        #expect(summary.hasSuffix("No cited facts."))
    }

    @Test("one fact is announced in the singular")
    func summaryCountsFacts() {
        let fact = ChartFact(
            id: "hypo-x",
            kind: .hypoOnset,
            anchor: at(0),
            end: at(50),
            title: [.observation(label: "BLACK BOX", value: nil, n: 1)],
            lines: [],
            severity: 3
        )
        let summary = LabChartAccessibility.summary(sheet: sheet(readings: 5), facts: [fact], unit: .mgdL)
        #expect(summary.hasSuffix("1 cited fact."))

        let two = LabChartAccessibility.summary(sheet: sheet(readings: 5), facts: [fact, fact], unit: .mgdL)
        #expect(two.hasSuffix("2 cited facts."))
    }

    @Test("an empty window says so rather than announcing an empty sheet")
    func summaryWithoutASheet() {
        #expect(LabChartAccessibility.summary(sheet: nil, facts: [], unit: .mgdL) == "Lab chart. No readings to plot.")
    }
}

// MARK: - Source guards

@Suite("Chart Lab fact copy guards")
struct ChartLabFactsCopyGuardTests {
    // #filePath → .../DOSBTSTests/ChartLabFactsTests.swift → repo root two levels up.
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// Everything the lab prints, plus the figure type itself.
    private static let scopes = ["App/Views/Overview/Lab", "Library/Content/LabFigure.swift"]

    private static func swiftFiles() -> [URL] {
        var files: [URL] = []
        for scope in scopes {
            let url = repoRoot.appendingPathComponent(scope)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else { continue }
                for case let file as URL in enumerator where file.pathExtension == "swift" {
                    files.append(file)
                }
            } else if url.pathExtension == "swift" {
                files.append(url)
            }
        }
        return files
    }

    private static func relativePath(of url: URL) -> String {
        let base = repoRoot.path.hasSuffix("/") ? repoRoot.path : repoRoot.path + "/"
        return url.path.hasPrefix(base) ? String(url.path.dropFirst(base.count)) : url.path
    }

    private static func isCommentLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
    }

    /// The STATIC text of a literal: interpolations are cut out.
    ///
    /// `"stack-\(dose.id)"` is an identity string, not copy — the reader never
    /// sees the word `dose`, and an identifier is not a claim. What a user reads
    /// is what stays after the `\(…)` spans are removed, so that is what the
    /// copy rules are applied to. A real violation (`"Take \(units)U now"`)
    /// still trips on its static half.
    private static func staticText(of literal: String) -> String {
        var result = ""
        var index = literal.startIndex
        while index < literal.endIndex {
            if literal[index] == "\\", literal.index(after: index) < literal.endIndex,
               literal[literal.index(after: index)] == "(" {
                var depth = 0
                var scan = literal.index(index, offsetBy: 2)
                while scan < literal.endIndex {
                    if literal[scan] == "(" { depth += 1 }
                    if literal[scan] == ")" {
                        if depth == 0 { break }
                        depth -= 1
                    }
                    scan = literal.index(after: scan)
                }
                index = scan < literal.endIndex ? literal.index(after: scan) : literal.endIndex
                continue
            }
            result.append(literal[index])
            index = literal.index(after: index)
        }
        return result
    }

    /// String literals on a line, contents only.
    private static func literals(in line: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: "\"((?:[^\"\\\\]|\\\\.)*)\"")
        let range = NSRange(line.startIndex ..< line.endIndex, in: line)
        return regex.matches(in: line, range: range).compactMap { match in
            guard let captured = Range(match.range(at: 1), in: line) else { return nil }
            return String(line[captured])
        }
    }

    /// Every scannable run of copy in a file, one entry per source line.
    ///
    /// Two things a naive per-literal scan misses, both of which would let real
    /// dosing copy through: a sentence SPLIT across concatenated literals
    /// (`"Ta" + "ke 2U now"`), and the body of a `\"\"\"` multi-line literal,
    /// which contains no quote characters at all on its own lines. So a line's
    /// literals are joined before matching, and multi-line bodies are tracked
    /// across lines and scanned whole.
    private static func copyRuns(in contents: String) throws -> [(line: Int, text: String)] {
        var runs: [(line: Int, text: String)] = []
        var insideMultiline = false

        for (index, line) in contents.components(separatedBy: "\n").enumerated() {
            let delimiters = line.components(separatedBy: "\"\"\"").count - 1

            if insideMultiline {
                if delimiters > 0 {
                    insideMultiline = false
                    // The tail before the closing delimiter is still copy.
                    if let head = line.components(separatedBy: "\"\"\"").first, !head.isEmpty {
                        runs.append((index + 1, head))
                    }
                } else {
                    runs.append((index + 1, line))
                }
                continue
            }

            if delimiters % 2 == 1 {
                insideMultiline = true
                continue
            }
            if isCommentLine(line) { continue }

            let joined = try literals(in: line).map { staticText(of: $0) }.joined()
            if !joined.isEmpty { runs.append((index + 1, joined)) }
        }

        return runs
    }

    @Test("the lab scans a non-empty set of sources — the guards below are not vacuous")
    func scopeResolves() {
        #expect(Self.swiftFiles().count >= 5)
    }

    /// Imperatives. `dose` is banned as a word; the standing safety footer is
    /// the one sanctioned use and is exempted by exact text.
    private static let bannedCopy = [
        "\\btake\\b", "\\btaking\\b", "\\binject", "\\bdose\\b", "\\bdosing\\b",
        "\\badminister", "\\bgive\\b", "units to", "you should", "bolus now", "bolus for", "correct with"
    ]

    @Test("no dosing language in anything the lab prints")
    func rule_noDosingLanguageInFactCopy() throws {
        let exempt: Set<String> = ["LAB · EXPERIMENTAL · NOT DOSE ADVICE"]
        let regexes = try Self.bannedCopy.map { try NSRegularExpression(pattern: $0, options: .caseInsensitive) }

        var hits: [String] = []
        for file in Self.swiftFiles() {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for run in try Self.copyRuns(in: contents) where !exempt.contains(run.text) {
                let range = NSRange(run.text.startIndex ..< run.text.endIndex, in: run.text)
                for regex in regexes where regex.firstMatch(in: run.text, range: range) != nil {
                    hits.append("\(Self.relativePath(of: file)):\(run.line): \"\(run.text)\"")
                }
            }
        }

        #expect(hits.isEmpty, "Dosing language in lab copy:\n\(hits.joined(separator: "\n"))")
    }

    @Test("the scan still bites — an imperative trips it, an interpolated identifier does not")
    func rule_scanDetectsRealCopy() throws {
        let regexes = try Self.bannedCopy.map { try NSRegularExpression(pattern: $0, options: .caseInsensitive) }

        func trips(_ literal: String) -> Bool {
            let copy = Self.staticText(of: literal)
            let range = NSRange(copy.startIndex ..< copy.endIndex, in: copy)
            return regexes.contains { $0.firstMatch(in: copy, range: range) != nil }
        }

        // Real copy, caught — including around an interpolation.
        #expect(trips("Take \\(units)U now"))
        #expect(trips("You should correct with 2U"))
        // Identity strings and honest facts, not caught.
        #expect(trips("stack-\\(dose.id.uuidString)") == false)
        #expect(trips("LAST BOLUS T-4h10") == false)
        #expect(trips("STACKED BOLUS") == false)
    }

    @Test("the scan reads split literals and multi-line bodies, not just single quoted runs")
    func rule_scanReadsSplitAndMultilineCopy() throws {
        let quote = "\"\"\""
        let source = [
            "let a = \"Ta\" + \"ke 2U now\"",
            "let b = " + quote,
            "You should give 2U for that",
            quote,
            "let c = \"stack-\\(dose.id)\""
        ].joined(separator: "\n")

        let runs = try Self.copyRuns(in: source).map(\.text)
        #expect(runs.contains("Take 2U now"))
        #expect(runs.contains("You should give 2U for that"))
        #expect(runs.contains("stack-"))

        let regexes = try Self.bannedCopy.map { try NSRegularExpression(pattern: $0, options: .caseInsensitive) }
        func trips(_ text: String) -> Bool {
            let range = NSRange(text.startIndex ..< text.endIndex, in: text)
            return regexes.contains { $0.firstMatch(in: text, range: range) != nil }
        }
        #expect(trips("Take 2U now"))
        #expect(trips("You should give 2U for that"))
        #expect(trips("stack-") == false)
        // The widened token list.
        #expect(trips("administer 2U"))
        #expect(trips("dosing guidance"))
        #expect(trips("taking insulin"))
        #expect(trips("bolus for 60g"))
    }

    @Test("every LabFigure in the lab is constructed with its sample size")
    func rule_everyFigureShipsWithN() throws {
        var hits: [String] = []

        for file in Self.swiftFiles() {
            let contents = try String(contentsOf: file, encoding: .utf8)
            let code = contents
                .components(separatedBy: "\n")
                .filter { !Self.isCommentLine($0) }
                .joined(separator: "\n")

            var search = code.startIndex
            while let found = code.range(of: "LabFigure(", range: search ..< code.endIndex) {
                var depth = 0
                var index = found.upperBound
                var closed = code.endIndex
                while index < code.endIndex {
                    let character = code[index]
                    if character == "(" { depth += 1 }
                    if character == ")" {
                        if depth == 0 { closed = index; break }
                        depth -= 1
                    }
                    index = code.index(after: index)
                }
                let arguments = String(code[found.upperBound ..< closed])
                if !arguments.contains("n:") {
                    hits.append("\(Self.relativePath(of: file)): LabFigure(\(arguments.prefix(60))…)")
                }
                search = closed == code.endIndex ? code.endIndex : code.index(after: closed)
            }
        }

        #expect(hits.isEmpty, "LabFigure built without its n:\n\(hits.joined(separator: "\n"))")
    }
}
