//
//  InsulinBatchBuilderTests.swift
//  DOSBTSTests
//
//  Pins the commit-set + staged-IOB rules for the Add Insulin batch staging
//  flow (DMNC-1413). See docs/plans/2026-07-18-insulin-batch-entry-plan.md.
//

import Foundation
import Testing
@testable import DOSBTSApp

@Suite("InsulinBatchBuilder")
struct InsulinBatchBuilderTests {

    // InsulinDelivery's init rounds `starts`/`ends` down to the start of the
    // minute (`toRounded(on: 1, .minute)`), so fixtures must already be
    // minute-aligned or equality checks against the raw input will spuriously
    // fail on the seconds component.
    private let starts = Date(timeIntervalSince1970: 1_700_000_000).toRounded(on: 1, .minute)
    private var ends: Date { starts.addingTimeInterval(3600) }

    private func makeDelivery(units: Double, type: InsulinType = .snackBolus) -> InsulinDelivery {
        InsulinDelivery(id: UUID(), starts: starts, ends: starts, units: units, type: type)
    }

    // MARK: - commitSet

    @Test("staged only (form empty, nil units) → staged unchanged")
    func stagedOnlyNilUnits() {
        let staged = [makeDelivery(units: 2), makeDelivery(units: 3)]
        let result = InsulinBatchBuilder.commitSet(
            staged: staged,
            currentUnits: nil,
            currentType: .mealBolus,
            starts: starts,
            ends: ends
        )
        #expect(result == staged)
        #expect(result.count == 2)
    }

    @Test("form only (nothing staged, valid units) → one entry")
    func formOnly() {
        let result = InsulinBatchBuilder.commitSet(
            staged: [],
            currentUnits: 4,
            currentType: .correctionBolus,
            starts: starts,
            ends: ends
        )
        #expect(result.count == 1)
        #expect(result.first?.units == 4)
        #expect(result.first?.type == .correctionBolus)
    }

    @Test("staged + valid form → staged plus form entry appended")
    func stagedPlusValidForm() {
        let staged = [makeDelivery(units: 2, type: .correctionBolus), makeDelivery(units: 3, type: .snackBolus)]
        let result = InsulinBatchBuilder.commitSet(
            staged: staged,
            currentUnits: 5,
            currentType: .mealBolus,
            starts: starts,
            ends: ends
        )
        #expect(result.count == 3)
        // Staged entries come first, in their original order.
        #expect(result[0].id == staged[0].id)
        #expect(result[1].id == staged[1].id)
        // The current-form entry is appended last.
        #expect(result[2].units == 5)
        #expect(result[2].type == .mealBolus)
    }

    @Test("staged + zero units form → staged only")
    func stagedPlusZeroUnitsForm() {
        let staged = [makeDelivery(units: 2)]
        let result = InsulinBatchBuilder.commitSet(
            staged: staged,
            currentUnits: 0,
            currentType: .mealBolus,
            starts: starts,
            ends: ends
        )
        #expect(result == staged)
        #expect(result.count == 1)
    }

    @Test("staged + nil units form → staged only")
    func stagedPlusNilUnitsForm() {
        let staged = [makeDelivery(units: 2)]
        let result = InsulinBatchBuilder.commitSet(
            staged: staged,
            currentUnits: nil,
            currentType: .mealBolus,
            starts: starts,
            ends: ends
        )
        #expect(result == staged)
        #expect(result.count == 1)
    }

    @Test("empty everything → empty array")
    func emptyEverything() {
        let result = InsulinBatchBuilder.commitSet(
            staged: [],
            currentUnits: nil,
            currentType: .mealBolus,
            starts: starts,
            ends: ends
        )
        #expect(result.isEmpty)
    }

    @Test("empty staged + zero units form → empty array")
    func emptyStagedZeroUnitsForm() {
        let result = InsulinBatchBuilder.commitSet(
            staged: [],
            currentUnits: 0,
            currentType: .mealBolus,
            starts: starts,
            ends: ends
        )
        #expect(result.isEmpty)
    }

    @Test("basal form entry keeps its own ends")
    func basalKeepsOwnEnds() {
        let result = InsulinBatchBuilder.commitSet(
            staged: [],
            currentUnits: 10,
            currentType: .basal,
            starts: starts,
            ends: ends
        )
        #expect(result.count == 1)
        #expect(result.first?.ends == ends)
        #expect(result.first?.starts == starts)
    }

    @Test("non-basal form entry gets ends == starts")
    func nonBasalEndsEqualsStarts() {
        for type: InsulinType in [.mealBolus, .snackBolus, .correctionBolus] {
            let result = InsulinBatchBuilder.commitSet(
                staged: [],
                currentUnits: 6,
                currentType: type,
                starts: starts,
                ends: ends
            )
            #expect(result.count == 1)
            #expect(result.first?.ends == starts)
        }
    }

    // MARK: - iobInputs

    @Test("iobInputs concatenates committed and staged, committed first")
    func iobInputsConcatenation() {
        let committed = [makeDelivery(units: 1), makeDelivery(units: 2)]
        let staged = [makeDelivery(units: 3)]
        let result = InsulinBatchBuilder.iobInputs(committed: committed, staged: staged)
        #expect(result.count == 3)
        #expect(result[0].id == committed[0].id)
        #expect(result[1].id == committed[1].id)
        #expect(result[2].id == staged[0].id)
    }

    @Test("iobInputs with empty staged returns committed unchanged")
    func iobInputsEmptyStaged() {
        let committed = [makeDelivery(units: 1)]
        let result = InsulinBatchBuilder.iobInputs(committed: committed, staged: [])
        #expect(result == committed)
    }

    @Test("iobInputs with empty committed returns staged unchanged")
    func iobInputsEmptyCommitted() {
        let staged = [makeDelivery(units: 1)]
        let result = InsulinBatchBuilder.iobInputs(committed: [], staged: staged)
        #expect(result == staged)
    }

    @Test("iobInputs with both empty returns empty")
    func iobInputsBothEmpty() {
        let result = InsulinBatchBuilder.iobInputs(committed: [], staged: [])
        #expect(result.isEmpty)
    }
}
