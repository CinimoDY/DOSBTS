//
//  AlarmProfile.swift
//  DOSBTS
//
//  Day/night alarm profile resolution. Shared between app and widget targets.
//

import Foundation

// MARK: - AlarmProfile

enum AlarmProfile {
    case day
    case night
}

// MARK: - App Group key constants

/// Raw string keys for the day/night alarm profile data mirrored into
/// `UserDefaults.shared` (App Group suite). Both the app's
/// AppGroupSharing middleware and the widget targets read/write these
/// keys directly via `UserDefaults.shared.set(_:forKey:)`.
enum AppGroupAlarmProfileKeys {
    static let dayAlarmHigh = "dayAlarmHigh"
    static let dayAlarmLow = "dayAlarmLow"
    static let nightAlarmHigh = "nightAlarmHigh"
    static let nightAlarmLow = "nightAlarmLow"
    static let nightStartHour = "nightStartHour"
    static let nightStartMinute = "nightStartMinute"
    static let nightEndHour = "nightEndHour"
    static let nightEndMinute = "nightEndMinute"

    static let allRequired = [
        dayAlarmHigh, dayAlarmLow, nightAlarmHigh, nightAlarmLow,
        nightStartHour, nightStartMinute, nightEndHour, nightEndMinute
    ]
}

// MARK: - Render-time threshold resolution

/// Resolved active-profile threshold pair. Returned by the widget +
/// Live Activity render-time resolvers so callers can render against
/// the active profile without duplicating the all-or-nothing fallback
/// logic.
struct ResolvedAlarmThresholds: Equatable {
    let alarmLow: Int
    let alarmHigh: Int
    let profile: AlarmProfile
}

/// Resolves the active-profile thresholds at the given clock time, given
/// a key-reader closure. Returns `nil` if any of the eight required keys
/// is missing — callers should fall back to legacy single-threshold values.
///
/// Used by both the Home Screen widget (reading from `UserDefaults.shared`)
/// and the Live Activity widget (reading from ContentState fields). Sharing
/// the resolution logic prevents widget/Live Activity drift on schedule edits.
func resolveActiveProfileThresholds(
    at date: Date,
    intReader: (String) -> Int?
) -> ResolvedAlarmThresholds? {
    guard
        let dayHigh = intReader(AppGroupAlarmProfileKeys.dayAlarmHigh),
        let dayLow = intReader(AppGroupAlarmProfileKeys.dayAlarmLow),
        let nightHigh = intReader(AppGroupAlarmProfileKeys.nightAlarmHigh),
        let nightLow = intReader(AppGroupAlarmProfileKeys.nightAlarmLow),
        let startH = intReader(AppGroupAlarmProfileKeys.nightStartHour),
        let startM = intReader(AppGroupAlarmProfileKeys.nightStartMinute),
        let endH = intReader(AppGroupAlarmProfileKeys.nightEndHour),
        let endM = intReader(AppGroupAlarmProfileKeys.nightEndMinute)
    else {
        return nil
    }

    let profile = resolveActiveAlarmProfile(
        at: date,
        nightStartHour: startH,
        nightStartMinute: startM,
        nightEndHour: endH,
        nightEndMinute: endM
    )

    return ResolvedAlarmThresholds(
        alarmLow: profile == .night ? nightLow : dayLow,
        alarmHigh: profile == .night ? nightHigh : dayHigh,
        profile: profile
    )
}

// MARK: - Boundary scheduling

/// Returns the next clock time at which the active alarm profile flips,
/// within `lookaheadSeconds` of `from`. Returns `nil` if no flip occurs in
/// the window (e.g., degenerate schedule, or the boundary is past the
/// lookahead). Used by the widget's timeline provider so the home-screen
/// widget refreshes exactly when the profile changes, rather than waiting
/// up to 15 minutes for the next reload tick.
///
/// Resolution: the returned time is the start-of-minute when the new
/// profile takes effect (per the [start, end) semantics of
/// `resolveActiveAlarmProfile`). Values are clamped to the same valid
/// hour/minute ranges as the resolver.
func nextAlarmProfileBoundary(
    from date: Date,
    nightStartHour: Int,
    nightStartMinute: Int,
    nightEndHour: Int,
    nightEndMinute: Int,
    lookaheadSeconds: TimeInterval = 15 * 60
) -> Date? {
    let sH = max(0, min(23, nightStartHour))
    let sM = max(0, min(59, nightStartMinute))
    let eH = max(0, min(23, nightEndHour))
    let eM = max(0, min(59, nightEndMinute))
    let startMinute = (sH * 60) + sM
    let endMinute = (eH * 60) + eM

    if startMinute == endMinute { return nil }

    let cal = Calendar.current
    let comps = cal.dateComponents([.hour, .minute], from: date)
    let currentMinute = ((comps.hour ?? 0) * 60) + (comps.minute ?? 0)

    // Compute "minutes until next boundary" — pick whichever boundary comes
    // sooner (start or end). Boundary is exclusive at end, inclusive at start.
    func minutesUntil(_ targetMinute: Int) -> Int {
        let diff = targetMinute - currentMinute
        return diff > 0 ? diff : diff + 24 * 60
    }
    let untilStart = minutesUntil(startMinute)
    let untilEnd = minutesUntil(endMinute)
    let untilNext = min(untilStart, untilEnd)

    let secondsUntil = TimeInterval(untilNext * 60) - TimeInterval(cal.component(.second, from: date))
    guard secondsUntil > 0, secondsUntil <= lookaheadSeconds else { return nil }

    return date.addingTimeInterval(secondsUntil)
}

// MARK: - Critical-low breakthrough

/// Critical-low breakthrough decision. Glucose readings below
/// `alarmLow - criticalLowMargin` should fire even when an alarm is
/// snoozed, because they represent a clinically dangerous low.
///
/// The margin is constant (15 mg/dL) per `GlucoseNotification.swift`.
/// Centralizing the decision lets us test it directly and ensures the
/// production middleware and tests stay in lockstep.
let criticalLowBreakthroughMargin = 15

func isCriticalLow(glucoseValue: Int, alarmLow: Int) -> Bool {
    glucoseValue < (alarmLow - criticalLowBreakthroughMargin)
}

// MARK: - Treatment prompt currency (DMNC-1560)

/// Width of the predictive-low "still relevant" zone above `alarmLow`. The
/// predictive flag clears on the first reading at or above
/// `alarmLow + predictiveLowClearMargin` (GlucoseNotification R8c); a
/// predictive treatment prompt is only current below that line.
let predictiveLowClearMargin = 10

/// Is a pending treatment prompt still about a real (or imminent) low?
///
/// The prompt is presented on foreground / cold launch, possibly hours after
/// the alarm that set it. This gates presentation on the *current* reading:
/// - no reading, or a reading 15+ min old (`GlucoseStaleness.veryStale`) → false
///   (no evidence; the hero already shows red staleness). The 5–14 min
///   `.stale` tier still presents — a BLE gap must not hide a genuine low.
/// - value below `alarmLow` → true.
/// - otherwise only for a predictive prompt that is still heading low: value
///   inside the clear zone, a known slope, and the same 20-min linear
///   projection the predictive alarm uses still crossing `alarmLow`.
///
/// Pure and UIKit-free so it is shared with the widget target and unit-tested.
func isTreatmentPromptCurrent(
    latestGlucose: SensorGlucose?,
    alarmLow: Int,
    predictive: Bool,
    now: Date = Date()
) -> Bool {
    guard let latestGlucose else { return false }

    if case .veryStale = GlucoseStaleness.of(readingTimestamp: latestGlucose.timestamp, now: now) {
        return false
    }

    let value = latestGlucose.glucoseValue
    if value < alarmLow {
        return true
    }

    guard predictive,
          value < alarmLow + predictiveLowClearMargin,
          let minuteChange = latestGlucose.minuteChange
    else {
        return false
    }

    return Double(value) + minuteChange * 20.0 < Double(alarmLow)
}

// MARK: - Resolution

/// Returns the active alarm profile for the given clock time and night-window schedule.
///
/// Window semantics: `[start, end)` — start is inclusive, end is exclusive.
/// Wrap across midnight (e.g., 22:00→07:00) is handled via minute-of-day comparison.
/// A degenerate schedule where `start == end` returns `.day` always (no slot is "night").
func resolveActiveAlarmProfile(
    at date: Date,
    nightStartHour: Int,
    nightStartMinute: Int,
    nightEndHour: Int,
    nightEndMinute: Int
) -> AlarmProfile {
    // Clamp inputs to valid ranges so a corrupted UserDefaults state can't produce
    // nonsense schedules. DatePicker can't surface out-of-range values; this guards
    // against direct manipulation or future code paths.
    let sH = max(0, min(23, nightStartHour))
    let sM = max(0, min(59, nightStartMinute))
    let eH = max(0, min(23, nightEndHour))
    let eM = max(0, min(59, nightEndMinute))
    let startMinute = (sH * 60) + sM
    let endMinute = (eH * 60) + eM

    if startMinute == endMinute {
        return .day
    }

    let components = Calendar.current.dateComponents([.hour, .minute], from: date)
    let currentMinute = ((components.hour ?? 0) * 60) + (components.minute ?? 0)

    if startMinute < endMinute {
        // Same-day window, e.g. 13:00 → 18:00
        return (currentMinute >= startMinute && currentMinute < endMinute) ? .night : .day
    } else {
        // Wraps midnight, e.g. 22:00 → 07:00
        return (currentMinute >= startMinute || currentMinute < endMinute) ? .night : .day
    }
}
