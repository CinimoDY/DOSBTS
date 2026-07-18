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
    /// The full set to commit on CONFIRM: staged entries plus the current
    /// form if it holds a valid (units > 0) entry the user never staged.
    ///
    /// Mirrors `AddInsulinView.save()`'s `ends` rule: basal entries keep the
    /// caller-supplied `ends`, all other types collapse to `ends == starts`
    /// (point-in-time dose).
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

        let endsTime = currentType == .basal ? ends : starts
        let currentEntry = InsulinDelivery(starts: starts, ends: endsTime, units: units, type: currentType)
        return staged + [currentEntry]
    }

    /// Deliveries the IOB stacking warning should consider: committed + staged.
    /// Order is stable (committed first) so any downstream consumer that
    /// relies on ordering (e.g. `computeIOB`'s "last" semantics) sees the
    /// same shape it would once these deliveries are actually committed.
    static func iobInputs(
        committed: [InsulinDelivery],
        staged: [InsulinDelivery]
    ) -> [InsulinDelivery] {
        committed + staged
    }
}
