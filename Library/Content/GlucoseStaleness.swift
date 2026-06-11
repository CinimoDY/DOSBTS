//
//  GlucoseStaleness.swift
//  DOSBTS
//
//  Shared staleness presentation logic (KTD-4): the Overview hero and the
//  persistent status bar must never disagree on stale salience, so the
//  thresholds and tiering live here, not in either view.
//

import Foundation

public enum GlucoseStaleness: Equatable {
    /// Reading is recent enough to act on without a warning.
    case fresh
    /// 5–14 minutes old — amber warning treatment.
    case stale(minutes: Int)
    /// 15+ minutes old — red treatment. Dosing on this is dangerous.
    case veryStale(minutes: Int)

    /// Warning appears at 5 minutes.
    public static let staleThresholdMinutes = 5
    /// Warning escalates to red at 15 minutes.
    public static let veryStaleThresholdMinutes = 15

    public static func of(readingTimestamp: Date, now: Date = Date()) -> GlucoseStaleness {
        let elapsed = Int(now.timeIntervalSince(readingTimestamp) / 60)
        if elapsed >= veryStaleThresholdMinutes {
            return .veryStale(minutes: elapsed)
        }
        if elapsed >= staleThresholdMinutes {
            return .stale(minutes: elapsed)
        }
        return .fresh
    }

    /// "X MIN AGO" — nil while fresh.
    public var minutesAgoLabel: String? {
        switch self {
        case .fresh:
            return nil
        case .stale(let minutes), .veryStale(let minutes):
            return "\(minutes) MIN AGO"
        }
    }
}
