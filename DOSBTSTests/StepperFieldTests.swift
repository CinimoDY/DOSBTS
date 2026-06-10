import Testing
@testable import DOSBTSApp

@Suite("StepperField")
struct StepperFieldTests {
    @Test("incrementing past upper bound clamps")
    func clampsUp() {
        var v: Double? = 49.5
        StepperField.increment(&v, step: 0.5, range: 0...50)
        #expect(v == 50.0)
        StepperField.increment(&v, step: 0.5, range: 0...50)
        #expect(v == 50.0)
    }

    @Test("decrementing nil treats it as 0 and clamps to lower bound")
    func clampsDown() {
        var v: Double? = nil
        StepperField.decrement(&v, step: 0.5, range: 0...50)
        #expect(v == 0.0)
    }
}

// MARK: - AddBloodGlucoseView conversion (DMNC-796 U6)

@Suite("AddBloodGlucoseView display-unit conversion")
struct BloodGlucoseConversionTests {

    @Test("mg/dL value round-trips unchanged")
    func mgdLRoundTrip() {
        #expect(AddBloodGlucoseView.mgdLValue(fromDisplay: 100, glucoseUnit: .mgdL) == 100)
    }

    @Test("mmol/L value converts to stored mg/dL")
    func mmolLConverts() {
        // 5.5 mmol/L / 0.0555 = 99.099… → 99 mg/dL
        #expect(AddBloodGlucoseView.mgdLValue(fromDisplay: 5.5, glucoseUnit: .mmolL) == 99)
    }

    @Test("empty field yields nil (Add disabled)")
    func emptyFieldNil() {
        #expect(AddBloodGlucoseView.mgdLValue(fromDisplay: nil, glucoseUnit: .mgdL) == nil)
    }

    @Test("out-of-range values are rejected in both units")
    func rangeClamps() {
        #expect(AddBloodGlucoseView.mgdLValue(fromDisplay: 39, glucoseUnit: .mgdL) == nil)
        #expect(AddBloodGlucoseView.mgdLValue(fromDisplay: 501, glucoseUnit: .mgdL) == nil)
        #expect(AddBloodGlucoseView.mgdLValue(fromDisplay: 1.0, glucoseUnit: .mmolL) == nil)
        #expect(AddBloodGlucoseView.mgdLValue(fromDisplay: 30.0, glucoseUnit: .mmolL) == nil)
    }

    @Test("bounds themselves are accepted")
    func boundsAccepted() {
        #expect(AddBloodGlucoseView.mgdLValue(fromDisplay: 40, glucoseUnit: .mgdL) == 40)
        #expect(AddBloodGlucoseView.mgdLValue(fromDisplay: 500, glucoseUnit: .mgdL) == 500)
    }

    @Test("display range converts for mmol/L users")
    func displayRangeConverted() {
        let range = AddBloodGlucoseView.displayRange(for: .mmolL)
        #expect(abs(range.lowerBound - 40.toMmolL()) < 0.0001)
        #expect(abs(range.upperBound - 500.toMmolL()) < 0.0001)
    }
}
