//
//  RatioLabView.swift
//  DOSBTSApp
//
//  Ratio Lab UI (DMNC-1299, WP-R3) — an insulin-to-carb-ratio (ICR) and
//  correction-factor (ISF) workbench. It *teaches the method*, estimates both
//  from the user's own logged data, and never emits a dosing command.
//
//  Screen composition (top → bottom), per docs/plans/2026-07-03-ratio-lab-plan.md
//  § WP-R3:
//    1. Explainer card (.info / cgaCyan) — what an ICR / ISF is.
//    2. ESTIMATES grid — 3 × StatCard (500 rule / your meals / 1800-rule ISF),
//       gated behind sample-size (`—` + n/5 counter until enough evidence) AND a
//       plausibility gate (implausible rule-derived numbers are suppressed).
//    3. `REFERENCE ESTIMATES — NOT DOSE ADVICE` caption.
//    4. COLLECTING EVIDENCE n/5 progress line + CLEAN EXPERIMENT checklist —
//       front-and-centre in the empty / low-data state (the guidance moment).
//    5. REFERENCE row — save the working estimate (display-only, `.setConfirmedICR`).
//    6. EVIDENCE table — bespoke `RatioEvidenceRow`; excluded rows dimmed with a
//       teaching tag (NO BOLUS / ENDED +54 / HYPO / LOW START / SMALL MEAL …).
//    7. Safety footer — the second fixed disclaimer.
//
//  Safety hard rules (enforced by copy review, not code): no imperative dosing
//  language, no carbs-in→units-out field, every number ships with N / spread,
//  both fixed disclaimers present. Every glucose figure shown here honours
//  `state.glucoseUnit` (mg/dL vs mmol/L) via the shared `asGlucose` formatter.
//
//  Loading model: there is no `ratioEvidenceLoading` flag (pure-trigger loads
//  fall through the reducer's `default:`), so an absent estimate *is* the
//  loading state → `FiguresLoadingView.inline`. The estimate is computed once
//  when `ratioEvidence` changes (memoized into `@State`), not on every unrelated
//  store publish. A re-opened screen shows the previous (in-memory, transient)
//  evidence until the fresh `.setRatioEvidence` lands — acceptable for this cold
//  path; we deliberately avoid a flash of empty state on re-entry.
//

import SwiftUI

// MARK: - RatioLabView

struct RatioLabView: View {
    // MARK: Internal

    @EnvironmentObject var store: DirectStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DOSSpacing.md) {
                explainerCard

                if let estimates {
                    content(for: estimates)
                } else {
                    loadingCard
                }
            }
            .padding(.horizontal, DOSSpacing.md)
            .padding(.vertical, DOSSpacing.md)
        }
        .background(AmberTheme.dosBlack)
        .dosNavigationTitle("Ratio Lab")
        .toolbarBackground(AmberTheme.dosBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            // Cold path: re-fetch on every appear so the estimates track the
            // latest logged data. Silently no-ops unless `.active` (middleware).
            store.dispatch(.loadRatioEvidence)
            recomputeEstimates()
        }
        .onChange(of: store.state.ratioEvidence) { _, _ in
            // Recompute only when the evidence actually changes — not on every
            // ~1/min glucose publish that re-renders this observing view.
            recomputeEstimates()
        }
    }

    // MARK: Private — memoized estimate

    @State private var estimates: RatioEstimates?

    private func recomputeEstimates() {
        if let evidence = store.state.ratioEvidence {
            estimates = RatioEstimator.estimate(evidence: evidence)
        } else {
            estimates = nil
        }
    }

    // MARK: Private — sections

    @ViewBuilder
    private func content(for estimates: RatioEstimates) -> some View {
        estimatesGrid(estimates)

        Text("REFERENCE ESTIMATES — NOT DOSE ADVICE")
            .font(DOSTypography.caption)
            .foregroundStyle(AmberTheme.amberDark)
            .frame(maxWidth: .infinity)

        // Empty / low-data guidance moment: surface progress toward the meal gate.
        if estimates.empiricalICR == nil {
            Text("COLLECTING EVIDENCE \(qualifyingMealCount(estimates))/\(RatioEstimator.minQualifyingMeals)")
                .font(DOSTypography.mono(size: 14, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(AmberTheme.amber)
                .frame(maxWidth: .infinity)
                .padding(.top, DOSSpacing.xxs)
        }

        referenceRow(estimates)

        if !estimates.scoredObservations.isEmpty {
            evidenceTable(estimates)
        }

        CleanExperimentCard(glucoseUnit: store.state.glucoseUnit)

        Text("ESTIMATES ARE EDUCATIONAL REFERENCE ONLY. DISCUSS RATIO CHANGES WITH YOUR CARE TEAM.")
            .font(DOSTypography.caption)
            .foregroundStyle(AmberTheme.amberDark)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, DOSSpacing.xs)
    }

    // MARK: Explainer

    private var explainerCard: some View {
        VStack(alignment: .leading, spacing: DOSSpacing.sm) {
            Text("WHAT IS AN ICR?")
                .dosHeader(AmberTheme.cgaCyan)

            Text("1:X means one unit of rapid insulin covers about X grams of carbs.")
            Text("ISF (correction factor) is how far one unit tends to drop your glucose.")
            Text("This lab estimates both from your own logged meals and insulin — it never tells you what to dose.")
        }
        .font(DOSTypography.bodySmall)
        .foregroundStyle(AmberTheme.amberLight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dosCard(.info)
    }

    // MARK: Estimates grid

    private func estimatesGrid(_ estimates: RatioEstimates) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: DOSSpacing.sm),
            GridItem(.flexible(), spacing: DOSSpacing.sm),
            GridItem(.flexible(), spacing: DOSSpacing.sm),
        ], spacing: DOSSpacing.sm) {
            StatCard(
                label: "500 RULE",
                value: fiveHundredValue(estimates),
                help: fiveHundredHelp(estimates)
            )
            StatCard(
                label: "YOUR MEALS",
                value: estimates.empiricalICR.map(RatioEstimator.icrLabel) ?? "—",
                help: yourMealsHelp(estimates)
            )
            StatCard(
                label: "1800 RULE ISF",
                value: isfValue(estimates),
                help: isfHelp(estimates)
            )
        }
    }

    // MARK: Reference row

    @ViewBuilder
    private func referenceRow(_ estimates: RatioEstimates) -> some View {
        // Prefer the empirical (observed) ratio; fall back to the 500-rule estimate
        // only when it is plausible (the same 2–50 g/U band the empirical path enforces).
        let settable = estimates.empiricalICR ?? (rulePlausible(estimates) ? estimates.fiveHundredRuleICR : nil)

        if let confirmed = store.state.confirmedICR {
            VStack(alignment: .leading, spacing: DOSSpacing.sm) {
                Text("REFERENCE").dosHeader()
                HStack {
                    Text("REF RATIO \(RatioEstimator.icrLabel(confirmed))")
                        .font(DOSTypography.numeral)
                        .foregroundStyle(AmberTheme.amber)
                    Spacer()
                    Button("CLEAR") {
                        store.dispatch(.setConfirmedICR(icr: nil))
                    }
                    .buttonStyle(.dosGhost)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dosCard(.panel)
        } else if let settable {
            VStack(alignment: .leading, spacing: DOSSpacing.sm) {
                Text("REFERENCE").dosHeader()
                Text("Save your working estimate here for quick reference. Display only.")
                    .font(DOSTypography.caption)
                    .foregroundStyle(AmberTheme.amberDark)
                Button("SET \(RatioEstimator.icrLabel(settable)) AS REFERENCE") {
                    store.dispatch(.setConfirmedICR(icr: settable))
                }
                .buttonStyle(.dosGhost)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dosCard(.panel)
        }
    }

    // MARK: Evidence table

    private func evidenceTable(_ estimates: RatioEstimates) -> some View {
        VStack(alignment: .leading, spacing: DOSSpacing.sm) {
            Text("EVIDENCE").dosHeader()

            // Newest first — the recent experiments read first. Keyed on the stable
            // meal id so SwiftUI re-identifies rows by meal, not list position.
            let rows = estimates.scoredObservations
                .sorted { $0.observation.meal.timestamp > $1.observation.meal.timestamp }

            ForEach(rows, id: \.observation.meal.id) { scored in
                RatioEvidenceRow(scored: scored, glucoseUnit: store.state.glucoseUnit)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dosCard(.panel)
    }

    // MARK: Loading

    private var loadingCard: some View {
        HStack {
            Spacer()
            FiguresLoadingView.inline
            Spacer()
        }
        .padding(.vertical, DOSSpacing.xl)
    }

    // MARK: Plausibility

    /// The rule-based ICR/ISF share one median TDD; if `500 / TDD` lands outside
    /// the same 2–50 g/U band the empirical path enforces, that TDD sample is
    /// suspect and BOTH rule cards are suppressed rather than anchoring a
    /// clinically implausible figure (e.g. `1:100` / `360`) on a safety screen.
    /// (Because ISF = 1800/TDD, ICR in [2,50] keeps ISF in ~[7,180] too.)
    private func rulePlausible(_ estimates: RatioEstimates) -> Bool {
        guard let icr = estimates.fiveHundredRuleICR else { return false }
        return icr >= RatioEstimator.minRatioGramsPerUnit && icr <= RatioEstimator.maxRatioGramsPerUnit
    }

    // MARK: Formatting helpers

    private func qualifyingMealCount(_ estimates: RatioEstimates) -> Int {
        estimates.scoredObservations.filter { $0.ratio != nil }.count
    }

    private func fiveHundredValue(_ estimates: RatioEstimates) -> String {
        guard let icr = estimates.fiveHundredRuleICR, rulePlausible(estimates) else { return "—" }
        return RatioEstimator.icrLabel(icr)
    }

    private func fiveHundredHelp(_ estimates: RatioEstimates) -> String {
        guard let tdd = estimates.averageTDD else {
            return "\(estimates.qualifyingDayCount)/\(RatioEstimator.minQualifyingDays) DAYS"
        }
        guard rulePlausible(estimates) else { return "TDD \(tdd.asInsulin())U · CHECK" }
        return "TDD \(tdd.asInsulin())U · \(estimates.qualifyingDayCount) DAYS"
    }

    private func yourMealsHelp(_ estimates: RatioEstimates) -> String {
        guard let spread = estimates.empiricalICRSpread else {
            return "\(qualifyingMealCount(estimates))/\(RatioEstimator.minQualifyingMeals) MEALS"
        }
        let low = Int(spread.lowerBound.rounded())
        let high = Int(spread.upperBound.rounded())
        return "n=\(qualifyingMealCount(estimates)) · \(low)–\(high) SPREAD"
    }

    /// ISF in the user's display unit via the shared `asGlucose` formatter
    /// (mg/dL integer, or mmol/L to one decimal — locale-correct).
    private func isfValue(_ estimates: RatioEstimates) -> String {
        guard let isf = estimates.eighteenHundredRuleISFMgDL, isf.isFinite, rulePlausible(estimates) else { return "—" }
        return Int(isf.rounded()).asGlucose(glucoseUnit: store.state.glucoseUnit)
    }

    private func isfHelp(_ estimates: RatioEstimates) -> String {
        guard estimates.eighteenHundredRuleISFMgDL != nil else {
            return "\(estimates.qualifyingDayCount)/\(RatioEstimator.minQualifyingDays) DAYS"
        }
        guard rulePlausible(estimates) else { return "CHECK TDD" }
        return store.state.glucoseUnit == .mmolL ? "MMOL/L PER UNIT" : "MG/DL PER UNIT"
    }
}

// MARK: - RatioEvidenceRow

/// One compact evidence line. Qualifying meals read `4 JUL 12:40 · PASTA …
/// 60g/5.0U → 1:12` in amber; excluded meals are dimmed to amberDark with the
/// exclusion reason as a teaching tag *replacing* the ratio — the exclusion is
/// the lesson. Deliberately not `MealItemRow` (wrong display model + swipe
/// affordances). Glucose figures in tags honour `glucoseUnit`.
private struct RatioEvidenceRow: View {
    let scored: ScoredMealObservation
    let glucoseUnit: GlucoseUnit

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DOSSpacing.xs) {
            VStack(alignment: .leading, spacing: 2) {
                Text(timestampLabel)
                    .font(DOSTypography.caption)
                    .foregroundStyle(AmberTheme.amberDark)
                Text(mealName)
                    .font(DOSTypography.bodySmall)
                    .foregroundStyle(isQualifying ? AmberTheme.amber : AmberTheme.amberDark)
                    .lineLimit(1)
            }

            Spacer(minLength: DOSSpacing.xs)

            VStack(alignment: .trailing, spacing: 2) {
                Text(macroLine)
                    .font(DOSTypography.microLabel)
                    .foregroundStyle(AmberTheme.textFaint)
                    .lineLimit(1)
                Text(resultText)
                    .font(isQualifying ? DOSTypography.numeral : DOSTypography.label)
                    .tracking(isQualifying ? 0 : 0.6)
                    .foregroundStyle(resultColor)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, DOSSpacing.xxs)
    }

    // MARK: Private

    private var meal: MealEntry { scored.observation.meal }
    private var isQualifying: Bool { scored.ratio != nil }

    /// Locale-aware date + time (respects the user's 12/24-hour clock and month
    /// abbreviation), uppercased for the DOS terminal look.
    private var timestampLabel: String {
        meal.timestamp
            .formatted(.dateTime.month(.abbreviated).day().hour().minute())
            .uppercased()
    }

    private var mealName: String {
        let trimmed = meal.mealDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "MEAL" : trimmed.uppercased()
    }

    /// `60g/5.0U` when both are known; falls back to just the carbs (or bolus)
    /// when the other is absent. Non-finite carbs are dropped rather than trapping.
    private var macroLine: String {
        let bolus = scored.observation.pairedBolusUnits
        let bolusPart = bolus > 0 ? "\(bolus.asInsulin())U" : nil
        guard let carbs = meal.carbsGrams, carbs.isFinite else {
            return bolusPart ?? ""
        }
        let carbsPart = "\(Int(carbs.rounded()))g"
        if let bolusPart { return "\(carbsPart)/\(bolusPart)" }
        return carbsPart
    }

    private var resultText: String {
        if let ratio = scored.ratio {
            return RatioEstimator.icrLabel(ratio)
        }
        return scored.exclusion.map {
            Self.tag(for: $0, baseline: scored.observation.impact.baselineGlucose, glucoseUnit: glucoseUnit)
        } ?? "—"
    }

    private var resultColor: Color {
        if isQualifying { return AmberTheme.amber }
        // A hypo is the safety-critical lesson — call it out in red.
        if case .hypoInWindow = scored.exclusion { return AmberTheme.cgaRed }
        return AmberTheme.amberDark
    }

    /// The teaching tag for each exclusion reason. `baselineOutOfRange` splits
    /// into LOW START / HIGH START from the recorded baseline; the return-delta
    /// tag is rendered in the user's glucose unit.
    private static func tag(for reason: MealExclusionReason, baseline: Int?, glucoseUnit: GlucoseUnit) -> String {
        switch reason {
        case .confounded: return "CONFOUNDED"
        case .noBolus: return "NO BOLUS"
        case .tinyBolus: return "TINY BOLUS"
        case .noBaseline: return "NO BASELINE"
        case .baselineOutOfRange:
            if let baseline, baseline < RatioEstimator.baselineMinMgDL { return "LOW START" }
            return "HIGH START"
        case .smallMeal: return "SMALL MEAL"
        case let .didNotReturnToBaseline(delta):
            let sign = delta >= 0 ? "+" : "-"
            return "ENDED \(sign)\(abs(delta).asGlucose(glucoseUnit: glucoseUnit))"
        case .hypoInWindow: return "HYPO"
        case .implausibleRatio: return "ODD RATIO"
        case .insufficientData: return "NO CGM"
        }
    }
}

// MARK: - CleanExperimentCard

/// The guidance checklist — always present. This is the "teach the method"
/// surface: how to run a meal that produces a clean, usable data point. The
/// glucose figures are sourced from the estimator's own qualification gates
/// (so the taught method can't drift from the code) and shown in the user's unit.
private struct CleanExperimentCard: View {
    let glucoseUnit: GlucoseUnit

    private var steps: [String] {
        let low = RatioEstimator.baselineMinMgDL.asGlucose(glucoseUnit: glucoseUnit)
        let high = RatioEstimator.baselineMaxMgDL.asGlucose(glucoseUnit: glucoseUnit)
        let tolerance = RatioEstimator.returnToBaselineToleranceMgDL.asGlucose(glucoseUnit: glucoseUnit)
        return [
            "Start in range \(low)–\(high) with no active IOB",
            "Eat a known-carb meal (packaged or weighed helps)",
            "Bolus your usual ratio; log carbs + units within 15 min",
            "Hands off for 2 h — no corrections, snacks, or exercise",
            "At 2 h: within ±\(tolerance) of start and no low → ratio held",
            "Ended high → ratio too weak; went low → too strong",
            "Repeat until 5 qualifying meals collect below",
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DOSSpacing.sm) {
            Text("CLEAN EXPERIMENT").dosHeader(AmberTheme.amber)

            VStack(alignment: .leading, spacing: DOSSpacing.xs) {
                ForEach(steps, id: \.self) { step in
                    HStack(alignment: .firstTextBaseline, spacing: DOSSpacing.xs) {
                        Text("[ ]")
                            .font(DOSTypography.bodySmall)
                            .foregroundStyle(AmberTheme.amber)
                        Text(step)
                            .font(DOSTypography.bodySmall)
                            .foregroundStyle(AmberTheme.amberLight)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dosCard(.panel)
    }
}
