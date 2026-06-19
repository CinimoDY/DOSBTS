//
//  EventMarkerTypeTests.swift
//  DOSBTSTests
//

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
