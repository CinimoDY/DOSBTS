//
//  EventMarkerTypeTests.swift
//  DOSBTSTests
//

import Foundation
import Testing
@testable import DOSBTSApp

@Suite("InsulinType → EventMarkerType mapping")
struct EventMarkerTypeTests {

    @Test("mealBolus maps to .bolus")
    func mealBolusMapsTobolus() {
        #expect(InsulinType.mealBolus.markerType == .bolus)
    }

    @Test("snackBolus maps to .bolus")
    func snackBolusMapsTobolus() {
        #expect(InsulinType.snackBolus.markerType == .bolus)
    }

    @Test("correctionBolus maps to .correction")
    func correctionBolusMapsToCorrection() {
        #expect(InsulinType.correctionBolus.markerType == .correction)
    }

    @Test("basal maps to .basal")
    func basalMapsToBasal() {
        #expect(InsulinType.basal.markerType == .basal)
    }

    @Test("all InsulinType cases have a distinct markerType (exhaustiveness guard)")
    func allCasesCovered() {
        let types = InsulinType.allCases
        #expect(types.count == 4)
        #expect(types.map(\.markerType).contains(.bolus))
        #expect(types.map(\.markerType).contains(.correction))
        #expect(types.map(\.markerType).contains(.basal))
    }
}

@Suite("Event marker chip row layout (DMNC-715)")
struct MarkerChipRowTests {
    private let t = Date(timeIntervalSince1970: 1_700_000_000)

    private func mk(_ type: EventMarkerType, _ value: Double) -> EventMarker {
        let id = UUID()
        return EventMarker(id: id.uuidString, time: t, type: type, label: "", rawValue: value, sourceID: id)
    }

    private func group(_ markers: [EventMarker]) -> ConsolidatedMarkerGroup {
        ConsolidatedMarkerGroup(id: "g", time: t, markers: markers)
    }

    @Test("all five event types collapse to exactly 3 rows (insulin → meal → exercise)")
    func allTypesCollapseToThreeRows() {
        let rows = group([
            mk(.bolus, 5), mk(.correction, 2), mk(.basal, 10),
            mk(.meal, 45), mk(.exercise, 20),
        ]).chipRows(isScored: false)

        #expect(rows.count == 3)
        #expect(rows[0].leadType == .bolus)   // insulin lane leads with the filled syringe
        #expect(rows[1].leadType == .meal)
        #expect(rows[2].leadType == .exercise)
    }

    @Test("insulin lane combines bolus, correction, basal as ordered segments")
    func insulinLaneCombinesSegments() {
        // Deliberately out of order to prove the builder enforces bolus → correction → basal.
        let rows = group([mk(.basal, 10), mk(.correction, 2), mk(.bolus, 5)]).chipRows(isScored: false)

        #expect(rows.count == 1)
        #expect(rows[0].segments.map(\.type) == [.bolus, .correction, .basal])
        #expect(rows[0].segments.map(\.label) == ["5U", "2Uc", "10Ub"])
    }

    @Test("correction-only group leads with the correction (filled-syringe) icon")
    func correctionOnlyLeadIcon() {
        let rows = group([mk(.correction, 3)]).chipRows(isScored: false)
        #expect(rows.count == 1)
        #expect(rows[0].leadType == .correction)
        #expect(rows[0].segments == [MarkerChipSegment(type: .correction, label: "3Uc")])
    }

    @Test("basal-only group leads with the basal (outline-syringe) icon")
    func basalOnlyLeadIcon() {
        let rows = group([mk(.basal, 12)]).chipRows(isScored: false)
        #expect(rows[0].leadType == .basal)
        #expect(rows[0].segments == [MarkerChipSegment(type: .basal, label: "12Ub")])
    }

    @Test("scored meal prefixes the meal segment with ★")
    func scoredMealStarPrefix() {
        let g = group([mk(.meal, 45)])
        #expect(g.chipRows(isScored: false)[0].segments[0].label == "45g")
        #expect(g.chipRows(isScored: true)[0].segments[0].label == "★45g")
    }

    @Test("multiple boluses collapse to a total with a count suffix")
    func multipleBolusesCollapse() {
        let rows = group([mk(.bolus, 4), mk(.bolus, 6)]).chipRows(isScored: false)
        #expect(rows[0].segments[0].label == "10U×2")
    }

    @Test("fractional units render with one decimal place")
    func fractionalUnits() {
        let rows = group([mk(.correction, 2.5)]).chipRows(isScored: false)
        #expect(rows[0].segments[0].label == "2.5Uc")
    }

    @Test("meal + exercise without insulin yields 2 rows, meal first")
    func mealAndExerciseNoInsulin() {
        let rows = group([mk(.exercise, 30), mk(.meal, 20)]).chipRows(isScored: false)
        #expect(rows.count == 2)
        #expect(rows[0].leadType == .meal)
        #expect(rows[1].leadType == .exercise)
    }
}
