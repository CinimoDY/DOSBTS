//
//  ChartLabOverlay.swift
//  DOSBTS
//
//  Chart Lab (DMNC-1500) overlay seam. P0 declares the FULL set of mark-sets so
//  the parallel P1–P5 PRs each fill exactly one arm of `LabOverlayMarks.marks(for:)`
//  and never fight over this enum.
//

/// One additive mark-set a lab tab switches on inside `LabChartView`.
enum ChartLabOverlay: Hashable, CaseIterable {
    case carbSizedMeals        // P2
    case mealResponseRibbons   // P2
    case residualMarks         // P2
    case regimeBands           // P2
    case nightContext          // P1 (sleep stages, HR, cross-midnight ribbon)
    case ghostBand             // P4
    case factPins              // P5

    /// Stable draw order (declaration order), so the mark tree a tab builds is
    /// deterministic no matter how the `Set` happens to iterate.
    var drawOrder: Int {
        ChartLabOverlay.allCases.firstIndex(of: self) ?? 0
    }
}

extension ReportType {
    /// Mark-sets a lab tab layers onto the lab chart. Empty for shipping tabs.
    var labOverlays: Set<ChartLabOverlay> {
        switch self {
        case .labMeals: return [.carbSizedMeals, .mealResponseRibbons, .residualMarks, .regimeBands, .factPins]
        // NOT `.mealResponseRibbons`: the night draws its own carried-in ribbon
        // from `.nightContext`, so carrying P2's arm too would draw it twice the
        // moment P2 lands. Swapping to P2's graded ribbon is a follow-up.
        case .labNight: return [.nightContext]
        case .labPatterns: return [.ghostBand]
        case .labSweep, .glucose, .timeInRange, .statistics: return []
        }
    }
}
