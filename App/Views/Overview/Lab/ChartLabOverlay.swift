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

// MARK: - ChartLabSizing

/// Sizes the lab's data-driven symbols. Pure, so the mapping is pinned by a
/// test rather than by eye.
enum ChartLabSizing {
    /// `symbolSize` is an AREA in pt², so carbs map linearly into area — that is
    /// what makes two dots look like "twice as much", rather than mapping to a
    /// radius (which would make a 60 g plate look four times a 15 g one).
    static let mealSymbolMinArea: Double = 40
    static let mealSymbolMaxArea: Double = 400
    /// Above this the dot stops growing: a 300 g outlier must not shrink a whole
    /// day of ordinary meals into identical specks.
    static let mealSymbolCarbCeiling: Double = 100

    static func mealSymbolSize(carbs: Double?) -> Double {
        guard let carbs, carbs > 0 else { return mealSymbolMinArea }
        let clamped = min(carbs, mealSymbolCarbCeiling)
        let span = mealSymbolMaxArea - mealSymbolMinArea
        return mealSymbolMinArea + span * (clamped / mealSymbolCarbCeiling)
    }
}

extension ReportType {
    /// Mark-sets a lab tab layers onto the lab chart. Empty for shipping tabs.
    var labOverlays: Set<ChartLabOverlay> {
        switch self {
        case .labMeals: return [.carbSizedMeals, .mealResponseRibbons, .residualMarks, .regimeBands, .factPins]
        case .labNight: return [.nightContext, .mealResponseRibbons]
        case .labPatterns: return [.ghostBand]
        case .labSweep, .glucose, .timeInRange, .statistics: return []
        }
    }
}
