import Testing
@testable import DOSBTSApp

@Suite("StagingPlateRow")
struct StagingPlateRowTests {
    @Test("amount change auto-scales carbs when ratio is set")
    func autoScale() {
        var item = EditableFoodItem(name: "Cheerios", carbsG: 22.5, baseServingG: 60, currentAmountG: 60, carbsPerG: 0.375)
        StagingPlateRowLogic.applyAmountChange(item: &item, newAmount: 120)
        #expect(item.currentAmountG == 120)
        #expect(item.carbsG == 45.0)
    }

    @Test("manual carb edit breaks the ratio link")
    func manualOverride() {
        var item = EditableFoodItem(name: "Cheerios", carbsG: 45, baseServingG: 60, currentAmountG: 120, carbsPerG: 0.375)
        StagingPlateRowLogic.applyCarbsChange(item: &item, newCarbs: 50)
        #expect(item.carbsG == 50)
        #expect(item.carbsPerG == nil)
    }

    @Test("amount over 10000 clamps")
    func clampsLargeAmount() {
        var item = EditableFoodItem(name: "Test", carbsG: 0, baseServingG: 100, currentAmountG: 100, carbsPerG: 0.5)
        StagingPlateRowLogic.applyAmountChange(item: &item, newAmount: 50000)
        #expect(item.currentAmountG == 10000)
    }

    @Test("summary text differs by amount presence")
    func summary() {
        let withAmount = EditableFoodItem(name: "Pasta", carbsG: 38, baseServingG: 120, currentAmountG: 120, carbsPerG: nil)
        let withoutAmount = EditableFoodItem(name: "Bacon", carbsG: 2, baseServingG: nil, currentAmountG: nil, carbsPerG: nil)
        #expect(StagingPlateRowLogic.summary(for: withAmount) == "120g · 38g C")
        #expect(StagingPlateRowLogic.summary(for: withoutAmount) == "2g C")
    }
}

// MARK: - Corrections attributed by item, not position (DMNC-1561)

@Suite("StagingPlateCorrections")
struct StagingPlateCorrectionsTests {
    private let original = [
        NutritionItem(name: "Rice", carbsG: 40),
        NutritionItem(name: "Chicken", carbsG: 0),
        NutritionItem(name: "Sauce", carbsG: 8),
    ]

    private func staged(_ name: String, _ carbs: Double, _ index: Int?) -> EditableFoodItem {
        EditableFoodItem(name: name, carbsG: carbs, originalIndex: index, source: index == nil ? .manual : .ai)
    }

    @Test("an untouched plate logs no corrections")
    func untouched() {
        let plate = [staged("Rice", 40, 0), staged("Chicken", 0, 1), staged("Sauce", 8, 2)]
        #expect(StagingPlateCorrections.compute(original: original, staged: plate).isEmpty)
    }

    @Test("a mid-list delete logs exactly one deletion — no shifted renames")
    func midListDelete() {
        // Rice deleted; Chicken and Sauce now sit at positions 0 and 1.
        let plate = [staged("Chicken", 0, 1), staged("Sauce", 8, 2)]
        let corrections = StagingPlateCorrections.compute(original: original, staged: plate)
        #expect(corrections.count == 1)
        #expect(corrections.first?.correctionType == .deleted)
        #expect(corrections.first?.originalName == "Rice")
    }

    @Test("a replacement after a delete is a nameChange against its own original")
    func replaceAfterDelete() {
        let plate = [staged("Chicken", 0, 1), staged("Sweet chili sauce", 15, 2)]
        let corrections = StagingPlateCorrections.compute(original: original, staged: plate)
        let rename = corrections.first { $0.correctionType == .nameChange }
        #expect(rename?.originalName == "Sauce")
        #expect(rename?.correctedName == "Sweet chili sauce")
        #expect(rename?.correctedCarbsG == 15)
        #expect(corrections.filter { $0.correctionType == .deleted }.map(\.originalName) == ["Rice"])
        #expect(corrections.count == 2)
    }

    @Test("carb-only edit is a carbChange; name-only edit keeps correctedCarbs nil")
    func carbAndNameOnly() {
        let plate = [staged("Rice", 55, 0), staged("Grilled chicken", 0, 1), staged("Sauce", 8, 2)]
        let corrections = StagingPlateCorrections.compute(original: original, staged: plate)
        #expect(corrections.count == 2)
        let carb = corrections.first { $0.correctionType == .carbChange }
        #expect(carb?.originalName == "Rice")
        #expect(carb?.correctedCarbsG == 55)
        let rename = corrections.first { $0.correctionType == .nameChange }
        #expect(rename?.correctedName == "Grilled chicken")
        #expect(rename?.correctedCarbsG == nil)
    }

    @Test("rows without an original index are additions, even mid-list")
    func additions() {
        let plate = [staged("Rice", 40, 0), staged("Popcorn", 20, nil), staged("Chicken", 0, 1), staged("Sauce", 8, 2)]
        let corrections = StagingPlateCorrections.compute(original: original, staged: plate)
        #expect(corrections.count == 1)
        #expect(corrections.first?.correctionType == .added)
        #expect(corrections.first?.correctedName == "Popcorn")
        #expect(corrections.first?.correctedCarbsG == 20)
    }

    @Test("reordering rows logs nothing")
    func reorder() {
        let plate = [staged("Sauce", 8, 2), staged("Rice", 40, 0), staged("Chicken", 0, 1)]
        #expect(StagingPlateCorrections.compute(original: original, staged: plate).isEmpty)
    }

    @Test("a duplicated or out-of-range index is treated as an addition")
    func defensiveIndices() {
        let plate = [staged("Rice", 40, 0), staged("Rice copy", 40, 0), staged("Ghost", 1, 9), staged("Chicken", 0, 1), staged("Sauce", 8, 2)]
        let corrections = StagingPlateCorrections.compute(original: original, staged: plate)
        #expect(corrections.map(\.correctionType) == [.added, .added])
    }

    @Test("new provenance fields default to a manual, unattributed row")
    func defaults() {
        let item = EditableFoodItem(name: "x", carbsG: 1)
        #expect(item.originalIndex == nil)
        #expect(item.source == .manual)
    }
}

// MARK: - Row factory + item-scoped AI merge (DMNC-1561)

@Suite("EditableFoodItem factories")
struct EditableFoodItemFactoryTests {
    @Test("a known serving sets amount and the carbs-per-gram link")
    func withServing() {
        let item = EditableFoodItem.make(name: "Cheerios", carbsG: 22.5, servingG: 30, originalIndex: nil, source: .barcode)
        #expect(item.baseServingG == 30)
        #expect(item.currentAmountG == 30)
        #expect(item.carbsPerG == 0.75)
        #expect(item.source == .barcode)
        #expect(item.originalIndex == nil)
    }

    @Test("no (or a zero) serving leaves the portion fields off")
    func withoutServing() {
        for serving in [nil, 0.0] as [Double?] {
            let item = EditableFoodItem.make(name: "Popcorn", carbsG: 20, servingG: serving, originalIndex: 2, source: .history)
            #expect(item.baseServingG == nil)
            #expect(item.currentAmountG == nil)
            #expect(item.carbsPerG == nil)
            #expect(item.originalIndex == 2)
        }
    }

    @Test("serving strings parse grams/ml and reject nonsense")
    func servingGrams() {
        #expect(EditableFoodItem.servingGrams(from: "1 serving (30g)") == 30)
        #expect(EditableFoodItem.servingGrams(from: "per 100g") == 100)
        #expect(EditableFoodItem.servingGrams(from: "250 ml") == 250)
        #expect(EditableFoodItem.servingGrams(from: "a handful") == nil)
        #expect(EditableFoodItem.servingGrams(from: "5000g") == nil)
        #expect(EditableFoodItem.servingGrams(from: nil) == nil)
    }

    private func estimate(_ description: String, _ items: [NutritionItem]) -> NutritionEstimate {
        NutritionEstimate(description: description, items: items, totalCarbsG: 0, confidence: .medium)
    }

    @Test("single-item answer: that item with its serving")
    func singleItemAnswer() {
        let r = estimate("Popcorn", [NutritionItem(name: "Popcorn", carbsG: 20, servingSize: "30g")]).singleRowReplacement
        #expect(r?.name == "Popcorn")
        #expect(r?.carbsG == 20)
        #expect(r?.servingG == 30)
    }

    @Test("multi-item answer: summed carbs under the description, no serving")
    func multiItemAnswer() {
        let r = estimate("Popcorn with butter", [
            NutritionItem(name: "Popcorn", carbsG: 20, servingSize: "30g"),
            NutritionItem(name: "Butter", carbsG: 0.5, servingSize: "10g"),
        ]).singleRowReplacement
        #expect(r?.name == "Popcorn with butter")
        #expect(r?.carbsG == 20.5)
        #expect(r?.servingG == nil)
    }

    @Test("empty answer merges nothing")
    func emptyAnswer() {
        #expect(estimate("?", []).singleRowReplacement == nil)
    }
}
