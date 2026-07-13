import Testing
import Foundation
@testable import DOSBTSApp

@Suite("InsulinImpact")
struct InsulinImpactTests {
    @Test("delta is glucoseAtPeak minus glucoseAtDose, signed")
    func deltaSign() {
        let dose = InsulinDelivery(starts: Date(), ends: Date(), units: 4.5, type: .mealBolus)
        let impact = InsulinImpact.compute(
            for: dose,
            glucoseAtDose: 182,
            glucoseAtPeak: 114,
            peakOffsetMinutes: 72,
            iobAtDose: 1.8,
            confounders: []
        )
        #expect(impact.deltaMgDL == -68)
    }

    @Test("Correction nadir below baseline yields a negative delta (empirical ISF semantics)")
    func correctionNegativeDelta() {
        // For a correction, glucoseAtPeak carries the post-dose nadir; an effective
        // correction fell, so deltaMgDL is negative and ISF = -delta / units.
        let dose = InsulinDelivery(starts: Date(), ends: Date(), units: 2, type: .correctionBolus)
        let impact = InsulinImpact.compute(
            for: dose,
            glucoseAtDose: 200,
            glucoseAtPeak: 140,
            peakOffsetMinutes: 90,
            iobAtDose: nil,
            confounders: []
        )
        #expect(impact.deltaMgDL == -60)
    }
}
