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

    /// On-screen label, deliberately separate from the persisted rawValue.
    var label: String {
        switch self {
        case .glucose: return "GLUCOSE"
        case .timeInRange: return "TIME IN RANGE"
        case .statistics: return "STATISTICS"
        }
    }
}
