//
//  InsulinBatchBuilder.swift
//  DOSBTS
//
//  Pure commit-set + staged-IOB helpers for the Add Insulin batch staging flow
//  (DMNC-1413). No UI, no Redux, no I/O — same "pure logic, exhaustively
//  unit-tested" shape as `RatioEstimator.swift` and `SparklineBuilder.swift`.
//
//  The single-entry constraint the batch flow replaces was entirely view-layer:
//  everything below the view (the `.addInsulinDelivery(insulinDeliveryValues:)`
//  action, the reducer's `append(contentsOf:)`, the one-transaction batch
//  insert, and all downstream middlewares) already accepts an array. This file
//  just computes what that array should contain.
//

import Foundation

enum InsulinBatchBuilder {
    /// Builds one delivery from form values, applying the basal-`ends` rule in
    /// ONE place: basal entries keep the caller-supplied `ends`, all other
    /// types collapse to `ends == starts` (point-in-time dose). Used by both
    /// the staging path (STAGE ENTRY) and `commitSet` so the rule can't drift.
    static func makeEntry(
        units: Double,
        type: InsulinType,
        starts: Date,
        ends: Date
    ) -> InsulinDelivery {
        let endsTime = type == .basal ? ends : starts
        return InsulinDelivery(id: UUID(), starts: starts, ends: endsTime, units: units, type: type)
    }

    /// The full set to commit on CONFIRM: staged entries plus the current
    /// form if it holds a valid (units > 0) entry the user never staged.
    static func commitSet(
        staged: [InsulinDelivery],
        currentUnits: Double?,
        currentType: InsulinType,
        starts: Date,
        ends: Date
    ) -> [InsulinDelivery] {
        guard let units = currentUnits, units > 0 else {
            return staged
        }

        return staged + [makeEntry(units: units, type: currentType, starts: starts, ends: ends)]
    }

    /// Deliveries the IOB stacking warning should consider: committed + staged.
    /// Order is stable (committed first) so any downstream consumer that
    /// relies on ordering (e.g. `computeIOB`'s "last" semantics) sees the
    /// same shape it would once these deliveries are actually committed.
    ///
    /// **Future-dated staged entries are clamped to `now` — WARNING INPUT
    /// ONLY.** `computeIOB` skips deliveries that haven't started yet (insulin
    /// not yet delivered has zero IOB), which is correct for committed history
    /// but would silently zero a staged pre-bolus (a future `starts` picked
    /// via the time picker). A staged pre-bolus is exactly the insulin the
    /// user is about to stack against, so the stacking warning must count it:
    /// over-warn, never under-warn. The clamp exists only in this warning
    /// input — the entries committed on CONFIRM keep their user-chosen future
    /// `starts` untouched.
    static func iobInputs(
        committed: [InsulinDelivery],
        staged: [InsulinDelivery],
        now: Date = Date()
    ) -> [InsulinDelivery] {
        let clampedStaged = staged.map { entry -> InsulinDelivery in
            guard entry.starts > now else { return entry }
            // Rebuild at `now`, preserving id/units/type. Non-basal `ends`
            // tracks `starts` (point dose); basal keeps its original span.
            return InsulinDelivery(
                id: entry.id,
                starts: now,
                ends: entry.type == .basal ? entry.ends : now,
                units: entry.units,
                type: entry.type
            )
        }
        return committed + clampedStaged
    }
}
