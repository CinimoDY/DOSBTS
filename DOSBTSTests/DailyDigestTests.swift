//
//  DailyDigestTests.swift
//  DOSBTSTests
//

import Foundation
import Testing
@testable import DOSBTSApp

// MARK: - DailyDigest Model Tests

@Suite("DailyDigest model")
struct DailyDigestModelTests {

    @Test("DailyDigest initializes with all fields and auto-generates UUID")
    func initWithAllFields() {
        let date = Date()
        let digest = DailyDigest(
            date: date, tir: 78.0, tbr: 5.0, tar: 17.0,
            avg: 142.0, stdev: 35.0, readings: 288,
            lowCount: 2, highCount: 3,
            totalCarbsGrams: 185.0, totalInsulinUnits: 24.0,
            totalExerciseMinutes: 30.0, mealCount: 3, insulinCount: 5
        )

        #expect(digest.id != UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
        #expect(digest.tir == 78.0)
        #expect(digest.tbr == 5.0)
        #expect(digest.tar == 17.0)
        #expect(digest.avg == 142.0)
        #expect(digest.readings == 288)
        #expect(digest.lowCount == 2)
        #expect(digest.highCount == 3)
        #expect(digest.totalCarbsGrams == 185.0)
        #expect(digest.totalInsulinUnits == 24.0)
        #expect(digest.totalExerciseMinutes == 30.0)
        #expect(digest.mealCount == 3)
        #expect(digest.insulinCount == 5)
        #expect(digest.aiInsight == nil)
        #expect(digest.generatedAt == nil)
    }

    @Test("Two digests with different dates are not equal")
    func differentDatesNotEqual() {
        let d1 = DailyDigest(
            date: Date(), tir: 78.0, tbr: 5.0, tar: 17.0,
            avg: 142.0, stdev: 35.0, readings: 288,
            lowCount: 0, highCount: 0,
            totalCarbsGrams: 0, totalInsulinUnits: 0,
            totalExerciseMinutes: 0, mealCount: 0, insulinCount: 0
        )
        let d2 = DailyDigest(
            date: Date().addingTimeInterval(-86400), tir: 78.0, tbr: 5.0, tar: 17.0,
            avg: 142.0, stdev: 35.0, readings: 288,
            lowCount: 0, highCount: 0,
            totalCarbsGrams: 0, totalInsulinUnits: 0,
            totalExerciseMinutes: 0, mealCount: 0, insulinCount: 0
        )
        #expect(d1 != d2)
    }

    @Test("DailyDigest with nil aiInsight and nil generatedAt")
    func preAIState() {
        let digest = DailyDigest(
            date: Date(), tir: 80.0, tbr: 3.0, tar: 17.0,
            avg: 135.0, stdev: 30.0, readings: 200,
            lowCount: 1, highCount: 2,
            totalCarbsGrams: 150.0, totalInsulinUnits: 20.0,
            totalExerciseMinutes: 0, mealCount: 2, insulinCount: 3
        )
        #expect(digest.aiInsight == nil)
        #expect(digest.generatedAt == nil)
    }

    @Test("DailyDigest with aiInsight populated")
    func withInsight() {
        var digest = DailyDigest(
            date: Date(), tir: 65.0, tbr: 10.0, tar: 25.0,
            avg: 160.0, stdev: 45.0, readings: 288,
            lowCount: 3, highCount: 5,
            totalCarbsGrams: 200.0, totalInsulinUnits: 28.0,
            totalExerciseMinutes: 45.0, mealCount: 4, insulinCount: 6
        )
        digest.aiInsight = "Your late dinner caused an overnight high."
        digest.generatedAt = Date()

        #expect(digest.aiInsight != nil)
        #expect(digest.generatedAt != nil)
    }
}

// MARK: - Structured insight parsing

@Suite("DigestInsight parsing")
struct DigestInsightParsingTests {
    @Test("well-formed JSON parses with all fields")
    func wellFormed() {
        let raw = """
        {"headline": "STEADY DAY — 84% IN RANGE", "grade": "good",
         "facts": [{"label": "MORNING SPIKE", "value": "290 @ 07:38", "tone": "bad"}],
         "tips": ["Pre-bolus 10 min earlier for breakfast"],
         "cheer": "Third day above 80%"}
        """
        let insight = DigestInsight.parse(raw)
        #expect(insight?.headline == "STEADY DAY — 84% IN RANGE")
        #expect(insight?.grade == .good)
        #expect(insight?.facts.count == 1)
        #expect(insight?.facts.first?.tone == .bad)
        #expect(insight?.tips == ["Pre-bolus 10 min earlier for breakfast"])
        #expect(insight?.cheer == "Third day above 80%")
    }

    @Test("code fences and surrounding prose are tolerated")
    func fencedJSON() {
        let raw = """
        Here is the insight:
        ```json
        {"headline": "ROUGH NIGHT", "grade": "rough", "facts": [], "tips": [], "cheer": null}
        ```
        """
        let insight = DigestInsight.parse(raw)
        #expect(insight?.headline == "ROUGH NIGHT")
        #expect(insight?.grade == .rough)
        #expect(insight?.cheer == nil)
    }

    @Test("unknown grade and tone fall back to safe defaults instead of failing")
    func unknownEnums() {
        let raw = """
        {"headline": "OK DAY", "grade": "excellent",
         "facts": [{"label": "X", "value": "1", "tone": "amazing"}], "tips": []}
        """
        let insight = DigestInsight.parse(raw)
        #expect(insight?.grade == .mixed)
        #expect(insight?.facts.first?.tone == .warn)
    }

    @Test("legacy plain-text insight returns nil (falls back to text rendering)")
    func legacyText() {
        let raw = "A steady day overall.\n\n- Morning spike to 290 at 07:38\n- Third evening high this week"
        #expect(DigestInsight.parse(raw) == nil)
    }

    @Test("facts and tips are capped at 3 and 2; empty strings dropped")
    func capping() {
        let raw = """
        {"headline": "H", "grade": "mixed",
         "facts": [{"label":"A","value":"1","tone":"good"},{"label":"B","value":"2","tone":"good"},
                   {"label":"C","value":"3","tone":"good"},{"label":"D","value":"4","tone":"good"}],
         "tips": ["one", "", "two", "three"], "cheer": "  "}
        """
        let insight = DigestInsight.parse(raw)
        #expect(insight?.facts.count == 3)
        #expect(insight?.tips == ["one", "two"])
        #expect(insight?.cheer == nil)
    }

    @Test("missing headline fails the parse")
    func missingHeadline() {
        #expect(DigestInsight.parse("{\"grade\": \"good\"}") == nil)
        #expect(DigestInsight.parse("{\"headline\": \"  \"}") == nil)
    }
}
