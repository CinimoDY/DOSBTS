//
//  HypoFilteredEntryTests.swift
//  DOSBTSTests
//
//  Pins the no-dead-end guarantee for the hypo-filtered food entry sheet
//  (DMNC-1028): during a treatment cycle the MEAL button routes to the
//  filtered sheet, and a user with zero hypo favourites + zero recents must
//  still have a way to log carbs (the "LOG OTHER FOOD" escape row).
//

@testable import DOSBTSApp
import Testing

@Suite("HypoFilteredEntryModel")
struct HypoFilteredEntryModelTests {

    @Test("filtered + zero hypo favourites: empty message AND escape row (no dead-end)")
    func filteredEmpty() {
        let model = HypoFilteredEntryModel.make(
            hypoFavoriteCount: 0,
            filterToHypoTreatments: true
        )
        #expect(model.showsEmptyHypoMessage == true)
        #expect(model.showsEscapeRow == true)
    }

    @Test("filtered + some hypo favourites: no empty message, escape row still present")
    func filteredWithFavorites() {
        let model = HypoFilteredEntryModel.make(
            hypoFavoriteCount: 2,
            filterToHypoTreatments: true
        )
        #expect(model.showsEmptyHypoMessage == false)
        #expect(model.showsEscapeRow == true)
    }

    @Test("unfiltered: no empty message, no escape row (manual entry lives in actions section)")
    func unfiltered() {
        let model = HypoFilteredEntryModel.make(
            hypoFavoriteCount: 0,
            filterToHypoTreatments: false
        )
        #expect(model.showsEmptyHypoMessage == false)
        #expect(model.showsEscapeRow == false)
    }

    @Test("filtered + other favourites exist: OTHER FAVOURITES shown (DMNC-1564)")
    func filteredWithOtherFavorites() {
        let model = HypoFilteredEntryModel.make(
            hypoFavoriteCount: 1,
            otherFavoriteCount: 3,
            filterToHypoTreatments: true
        )
        #expect(model.showsOtherFavourites == true)
        #expect(model.showsEmptyHypoMessage == false)
    }

    @Test("filtered + no hypo favourites but other favourites: empty message AND other section")
    func filteredNoHypoButOthers() {
        let model = HypoFilteredEntryModel.make(
            hypoFavoriteCount: 0,
            otherFavoriteCount: 2,
            filterToHypoTreatments: true
        )
        #expect(model.showsEmptyHypoMessage == true)
        #expect(model.showsOtherFavourites == true)
        #expect(model.showsEscapeRow == true)
    }

    @Test("filtered + no other favourites: no OTHER FAVOURITES section")
    func filteredNoOthers() {
        let model = HypoFilteredEntryModel.make(
            hypoFavoriteCount: 2,
            otherFavoriteCount: 0,
            filterToHypoTreatments: true
        )
        #expect(model.showsOtherFavourites == false)
    }

    @Test("unfiltered: never shows OTHER FAVOURITES")
    func unfilteredNoOthers() {
        let model = HypoFilteredEntryModel.make(
            hypoFavoriteCount: 0,
            otherFavoriteCount: 5,
            filterToHypoTreatments: false
        )
        #expect(model.showsOtherFavourites == false)
    }
}
