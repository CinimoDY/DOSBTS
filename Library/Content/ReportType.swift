//
//  ReportType.swift
//  DOSBTS
//

enum ReportType: String, CaseIterable {
    // Raw values are UserDefaults persistence keys — keep them stable even if
    // the on-screen labels change, or saved selections silently reset.
    case glucose
    case timeInRange
    case statistics
    // Chart Lab (DMNC-1500) — experimental, hidden unless `showChartLab`.
    case labMeals
    case labNight
    case labSweep
    case labPatterns

    /// On-screen label, deliberately separate from the persisted rawValue.
    var label: String {
        switch self {
        case .glucose: return "GLUCOSE"
        case .timeInRange: return "TIME IN RANGE"
        case .statistics: return "STATISTICS"
        case .labMeals: return "LAB: MEALS"
        case .labNight: return "LAB: NIGHT"
        case .labSweep: return "LAB: SWEEP"
        case .labPatterns: return "LAB: PATTERNS"
        }
    }

    /// Experimental surface, gated by `showChartLab`.
    var isLab: Bool {
        switch self {
        case .labMeals, .labNight, .labSweep, .labPatterns: return true
        case .glucose, .timeInRange, .statistics: return false
        }
    }

    /// True when the zoom row is the 7d / 30d / 90d / ALL day window.
    var usesDayWindow: Bool {
        switch self {
        case .timeInRange, .statistics, .labSweep, .labPatterns: return true
        case .glucose, .labMeals, .labNight: return false
        }
    }

    /// Row order, lab cases filtered out when the lab is off.
    static func visible(labEnabled: Bool) -> [ReportType] {
        allCases.filter { labEnabled || !$0.isLab }
    }

    // The switches above are exhaustive on purpose: adding a case makes the
    // compiler point at every site that has to decide something about it.
}
