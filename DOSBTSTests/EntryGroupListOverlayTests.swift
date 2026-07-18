import Testing
import Foundation
@testable import DOSBTSApp

@Suite("EntryGroupListOverlay sub-lines")
struct EntryGroupListOverlayTests {
    @Test("meal sub-line shows IN PROGRESS within 2-hour window")
    func mealInProgress() {
        let m = MealEntry(timestamp: Date().addingTimeInterval(-30 * 60), mealDescription: "Pasta", carbsGrams: 45, analysisSessionId: nil)
        let line = EntryGroupListOverlay.subline(
            for: .meal(m),
            itemCount: 3,
            mealImpact: nil,
            personalFoodAvg: nil,
            glucoseUnit: .mgdL,
            iob: nil,
            paired: false,
            confounders: []
        )
        #expect(line.contains("IN PROGRESS"))
    }

    @Test("meal sub-line shows mmol/L delta when unit is mmol")
    func mealMmol() {
        let m = MealEntry(timestamp: Date().addingTimeInterval(-3 * 3600), mealDescription: "Pasta", carbsGrams: 45, analysisSessionId: nil)
        let impact = MealImpact(mealEntryId: m.id, baselineGlucose: 117, peakGlucose: 189, deltaMgDL: 72, timeToPeakMinutes: 105, isClean: true, timestamp: m.timestamp)
        let line = EntryGroupListOverlay.subline(
            for: .meal(m),
            itemCount: 3,
            mealImpact: impact,
            personalFoodAvg: nil,
            glucoseUnit: .mmolL,
            iob: nil,
            paired: false,
            confounders: []
        )
        #expect(line.contains("4.0 mmol/L"))   // 72 mg/dL ÷ 18 ≈ 4.0
    }

    @Test("meal sub-line includes PersonalFood avg with observation count when available")
    func mealPersonalFood() {
        let m = MealEntry(timestamp: Date().addingTimeInterval(-3 * 3600), mealDescription: "Pasta", carbsGrams: 45, analysisSessionId: UUID())
        let impact = MealImpact(mealEntryId: m.id, baselineGlucose: 117, peakGlucose: 189, deltaMgDL: 72, timeToPeakMinutes: 105, isClean: true, timestamp: m.timestamp)
        let line = EntryGroupListOverlay.subline(
            for: .meal(m),
            itemCount: 3,
            mealImpact: impact,
            personalFoodAvg: PersonalFoodGlycemic(avgDelta: 68, observationCount: 4),
            glucoseUnit: .mgdL,
            iob: nil,
            paired: false,
            confounders: []
        )
        #expect(line.contains("avg +68"))
        #expect(line.contains("(4)"))
    }

    @Test("insulin sub-line shows IOB when above threshold")
    func insulinIOB() {
        let i = InsulinDelivery(starts: Date(), ends: Date(), units: 4.5, type: .mealBolus)
        let line = EntryGroupListOverlay.subline(
            for: .insulin(i),
            itemCount: 1,
            mealImpact: nil,
            personalFoodAvg: nil,
            glucoseUnit: .mgdL,
            iob: 1.8,
            paired: false,
            confounders: []
        )
        #expect(line.contains("IOB 1.8U"))
    }

    @Test("insulin sub-line shows paired w/ meal when grouped with a meal")
    func insulinPaired() {
        let i = InsulinDelivery(starts: Date(), ends: Date(), units: 3.0, type: .correctionBolus)
        let line = EntryGroupListOverlay.subline(
            for: .insulin(i),
            itemCount: 1,
            mealImpact: nil,
            personalFoodAvg: nil,
            glucoseUnit: .mgdL,
            iob: nil,
            paired: true,
            confounders: []
        )
        #expect(line.contains("paired w/ meal"))
    }

    @Test("insulin sub-line falls back to type label when no IOB and unpaired")
    func insulinTypeFallback() {
        let i = InsulinDelivery(starts: Date(), ends: Date(), units: 8.0, type: .basal)
        let line = EntryGroupListOverlay.subline(
            for: .insulin(i),
            itemCount: 1,
            mealImpact: nil,
            personalFoodAvg: nil,
            glucoseUnit: .mgdL,
            iob: nil,
            paired: false,
            confounders: []
        )
        // No IOB, not paired — should show the type's localizedDescription
        #expect(!line.isEmpty)
    }

    @Test("exercise sub-line formats duration and activity type")
    func exerciseFormatting() {
        let e = ExerciseEntry(
            startTime: Date(),
            endTime: Date().addingTimeInterval(30 * 60),
            activityType: "Running",
            durationMinutes: 30,
            activeCalories: 250,
            source: nil
        )
        let line = EntryGroupListOverlay.subline(
            for: .exercise(e),
            itemCount: 1,
            mealImpact: nil,
            personalFoodAvg: nil,
            glucoseUnit: .mgdL,
            iob: nil,
            paired: false,
            confounders: []
        )
        #expect(line.contains("30 min"))
        #expect(line.contains("Running"))
    }
}

@Suite("EntryGroupListOverlay row helpers")
struct EntryGroupListOverlayRowHelperTests {
    /// A local `HH:mm` formatter matching the overlay's private one, so the
    /// assertions stay timezone-agnostic.
    private static let hhmm: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    // MARK: - rowTime

    @Test("rowTime uses the insulin delivery's start for insulin rows")
    func rowTimeUsesInsulinStart() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let markerTime = start.addingTimeInterval(3600)   // deliberately differs from start
        let marker = EventMarker(id: "b1", time: markerTime, type: .bolus, label: "5U", rawValue: 5, sourceID: UUID())
        let delivery = InsulinDelivery(starts: start, ends: start, units: 5, type: .mealBolus)

        let out = EntryGroupListOverlay.rowTime(for: marker, insulin: delivery)
        #expect(out == Self.hhmm.string(from: start))
        #expect(out != Self.hhmm.string(from: markerTime))
    }

    @Test("rowTime uses the marker time for meal rows")
    func rowTimeUsesMarkerTimeForMeal() {
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let marker = EventMarker(id: "m1", time: t, type: .meal, label: "30g", rawValue: 30, sourceID: UUID())
        #expect(EntryGroupListOverlay.rowTime(for: marker, insulin: nil) == Self.hhmm.string(from: t))
    }

    @Test("rowTime falls back to marker time when the insulin lookup is missing")
    func rowTimeInsulinFallback() {
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let marker = EventMarker(id: "c1", time: t, type: .correction, label: "2Uc", rawValue: 2, sourceID: UUID())
        #expect(EntryGroupListOverlay.rowTime(for: marker, insulin: nil) == Self.hhmm.string(from: t))
    }

    // MARK: - isEditable

    @Test("isEditable is true for meal and every insulin type, false for exercise")
    func isEditableMapping() {
        #expect(EntryGroupListOverlay.isEditable(.meal))
        #expect(EntryGroupListOverlay.isEditable(.bolus))
        #expect(EntryGroupListOverlay.isEditable(.correction))
        #expect(EntryGroupListOverlay.isEditable(.basal))
        #expect(!EntryGroupListOverlay.isEditable(.exercise))
    }

    // MARK: - deleteKind

    @Test("deleteKind maps each type to its whole-record delete")
    func deleteKindMapping() {
        #expect(EntryGroupListOverlay.deleteKind(for: .meal) == .meal)
        #expect(EntryGroupListOverlay.deleteKind(for: .bolus) == .insulin)
        #expect(EntryGroupListOverlay.deleteKind(for: .correction) == .insulin)
        #expect(EntryGroupListOverlay.deleteKind(for: .basal) == .insulin)
        #expect(EntryGroupListOverlay.deleteKind(for: .exercise) == .exercise)
    }
}
