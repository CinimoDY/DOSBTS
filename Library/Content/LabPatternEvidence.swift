//
//  LabPatternEvidence.swift
//  DOSBTS
//
//  Chart Lab P4 (DMNC-1503) — the multi-day evidence behind `LAB: PATTERNS`.
//
//  Transient state: loaded on demand when the tab appears (and again when the
//  day chips change), never persisted. It is the SAME read the clinic report
//  uses (`getClinicReportData(days:)` — one asyncRead, no writes); the lab just
//  derives different things from it.
//
//  Nothing here is dosing advice: it is a description of what this person's own
//  days have looked like, with the sample size attached to every number.
//

import Foundation

struct LabPatternEvidence: Equatable {
    /// The look-back actually used — already capped (see `cappedDays`), so the
    /// UI can label the band with this number and be telling the truth.
    let days: Int
    /// 24 entries, hour 0...23 (`ClinicReportBuilder.hourlyPatterns`).
    let hourly: [HourlyPattern]
    /// The window's raw readings, for the same-hour drill.
    let readings: [SensorGlucose]
    let period: DateInterval

    /// The band never looks back further than this. `DaysZoom.allDays` is the
    /// 9999-day sentinel the statistics SQL uses for "ALL"; handing that to a
    /// per-hour percentile would mean fetching every reading the user has ever
    /// had to describe "a usual hour", which is neither faster nor truer than
    /// 90 days.
    static let maxDays = 90

    static func cappedDays(_ days: Int) -> Int {
        min(max(days, 1), maxDays)
    }

    /// The day windows `ChartZoomRow` actually offers. Mirrors the private
    /// `DaysZoom` in `ChartToolbar.swift` (7 / 30 / 90 / ALL) — kept here so the
    /// lab can tell "the user picked this window" from "the toolbar has not
    /// normalised the persisted value yet", without reaching into a view file.
    static let chipWindows: Set<Int> = [7, 30, 90, 9999]

    static func isChipWindow(_ days: Int) -> Bool {
        chipWindows.contains(days)
    }
}
