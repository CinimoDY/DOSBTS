//
//  InsulinImpact.swift
//  DOSBTS
//

import Foundation

enum InsulinConfounder: Equatable {
    case stackedBolus(units: Double)
    case exerciseInWindow
    case correctionForLow
    /// A carb-bearing meal fell in the correction's effect window — its glucose rise
    /// masks the correction's isolated drop, so an ISF read off it would be wrong.
    case mealInWindow
}

struct InsulinImpact: Equatable {
    let dose: InsulinDelivery
    let glucoseAtDose: Int?
    let glucoseAtPeak: Int?
    let peakOffsetMinutes: Int?
    let iobAtDose: Double?
    let confounders: [InsulinConfounder]

    /// Signed glucose change from dose to the observed peak effect. For a *correction*
    /// dose `glucoseAtPeak` carries the post-dose nadir, so an effective correction is
    /// negative (glucose fell); empirical ISF = `-deltaMgDL / dose.units`.
    var deltaMgDL: Int? {
        guard let g0 = glucoseAtDose, let g1 = glucoseAtPeak else { return nil }
        return g1 - g0
    }

    static func compute(
        for dose: InsulinDelivery,
        glucoseAtDose: Int?,
        glucoseAtPeak: Int?,
        peakOffsetMinutes: Int?,
        iobAtDose: Double?,
        confounders: [InsulinConfounder]
    ) -> InsulinImpact {
        InsulinImpact(
            dose: dose,
            glucoseAtDose: glucoseAtDose,
            glucoseAtPeak: glucoseAtPeak,
            peakOffsetMinutes: peakOffsetMinutes,
            iobAtDose: iobAtDose,
            confounders: confounders
        )
    }
}

// MARK: - Correction scoring (empirical ISF, DMNC-1303)

/// Why a candidate correction bolus did not qualify for empirical-ISF estimation.
/// These double as the teaching tags the Ratio Lab shows on dimmed evidence rows —
/// the exclusion reason *is* the lesson about what a clean correction looks like.
enum CorrectionExclusionReason: Equatable {
    /// No CGM reading within the baseline tolerance of the dose.
    case noBaseline
    /// Started below the correction-relevant floor — a low invites rescue carbs, not a correction.
    case lowStart
    /// A carb-bearing meal fell in the effect window (its rise masks the drop).
    case mealInWindow
    /// Another bolus overlapped the effect window (can't attribute the drop to this dose).
    case stacked
    /// Exercise overlapped the effect window (amplifies the drop independent of insulin).
    case exercise
    /// Too few CGM readings in the effect window to trust the nadir.
    case noCGM
    /// Glucose did not fall (nadir ≥ baseline) — nothing to read an ISF from.
    case rose
    /// Dose too small to attribute an ISF to reliably.
    case tinyDose
    /// Computed ISF outside the clinically plausible band.
    case oddISF
}

/// A candidate correction after scoring: exactly one of `isfMgDLPerUnit` (qualified)
/// or `exclusion` (rejected) is non-nil. The full list — qualified and rejected — is
/// surfaced to the Ratio Lab's CORRECTIONS evidence table.
struct ScoredCorrectionObservation: Equatable {
    let impact: InsulinImpact
    /// Observed mg/dL drop per unit when the correction qualifies; `nil` when excluded.
    let isfMgDLPerUnit: Double?
    /// Why the correction was excluded; `nil` when it qualifies.
    let exclusion: CorrectionExclusionReason?
}
