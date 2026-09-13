//
//  LabFigure.swift
//  DOSBTS
//
//  Chart Lab (DMNC-1500 / P5): a number the lab is allowed to show.
//
//  The whole type exists for one invariant: it CANNOT be constructed without
//  its sample size. There is exactly one initializer and `n` has no default, so
//  "a number without its n" is a compile error rather than a review comment —
//  the same discipline Ratio Lab enforces by hand (`RatioLabView.swift:23-26`).
//
//  Glucose-family values (`glucose`, `delta`, `median`, `percentile`, `band`)
//  are stored in mg/dL, the app's internal unit, exactly as they come off
//  `SensorGlucose.glucoseValue`. `LabCaption` converts them to the user's
//  display unit at render time — a figure never carries a converted number,
//  because a converted number that meets a second converter is a bug
//  (see P0's readout: `Int.asGlucose` on an already-converted value).
//

import Foundation

// MARK: - LabFigure

struct LabFigure: Equatable, Codable {
    // MARK: Lifecycle

    /// The ONLY initializer. `n` is required and has no default: a lab number
    /// cannot exist without the sample it came from.
    init(
        kind: Kind,
        value: Double,
        unit: String,
        n: Int,
        spread: ClosedRange<Double>? = nil,
        window: DateInterval? = nil,
        label: String? = nil,
        citesSampleSize: Bool = true
    ) {
        self.kind = kind
        self.value = value
        self.unit = unit
        self.n = n
        self.spread = spread
        self.window = window
        self.label = label
        self.citesSampleSize = citesSampleSize
    }

    // MARK: Internal

    enum Kind: String, Codable {
        /// A change in glucose (mg/dL). Rendered with an explicit `+` when positive.
        case delta
        /// Minutes from a meal to its peak.
        case peakMinutes
        /// A glucose value (mg/dL).
        case glucose
        case iob
        /// A logged insulin delivery, in units.
        case insulin
        /// Carbs on board — placeholder until W2 ships a real number.
        case cob
        /// Logged carbohydrate, in grams.
        case carbs
        /// A count of things (episodes, meals, similar meals).
        case count
        /// The sample size itself, e.g. `n=24 RDG`.
        case sampleCount
        case median
        case percentile
        /// A range (`spread`) rendered as `lo–hi`, e.g. the tight-control band.
        case band
        /// A span of minutes.
        case duration

        /// Values in mg/dL that must be converted before they are shown.
        var isGlucoseFamily: Bool {
            switch self {
            case .glucose, .delta, .median, .percentile, .band: return true
            case .peakMinutes, .iob, .insulin, .cob, .carbs, .count, .sampleCount, .duration: return false
            }
        }

        /// Kinds where zero is itself the fact. `0 HYPO` is a true statement;
        /// a glucose of "0" is not, so every other kind renders an em dash when
        /// it has no sample behind it.
        var printsAtZeroSampleSize: Bool {
            self == .count || self == .sampleCount
        }
    }

    let kind: Kind
    /// mg/dL for the glucose family; units for insulin; grams for carbs;
    /// minutes for durations; a plain count otherwise.
    let value: Double
    /// Printed suffix. Empty means "no suffix" — the chart's own axis carries
    /// the unit on compact card lines. For the glucose family a non-empty unit
    /// is replaced by the user's display unit at render time.
    let unit: String
    /// The sample this number came from. `0` means "no data", and renders as
    /// an em dash rather than a zero.
    let n: Int
    /// An interquartile (or band) range in the same units as `value`.
    let spread: ClosedRange<Double>?
    /// The window the figure was derived over, when that is not obvious.
    let window: DateInterval?
    /// Printed before the number, e.g. `T-0`, `IOB`, `LAST BOLUS T-4h10`.
    let label: String?
    /// Whether the rendered text ends with `· n=<n>`. Aggregates say so;
    /// a directly observed value (a logged bolus, the reading at T-0) carries
    /// its `n` without shouting it, and a line's closing `.sampleCount` figure
    /// states it once for the whole line.
    let citesSampleSize: Bool
}

// MARK: - LabFactItem

/// One element of a lab line.
///
/// Numbers can ONLY enter through `.figure`, which cannot exist without its
/// sample size. `.observation` restates a record verbatim — a tag, an activity
/// type, a pair of heart rates — and carries the number of records it restates
/// so that "no record" (`n == 0`) renders as an em dash instead of silence.
enum LabFactItem: Equatable {
    case figure(LabFigure)
    case observation(label: String, value: String?, n: Int)
}
