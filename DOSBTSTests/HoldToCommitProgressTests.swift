//
//  HoldToCommitProgressTests.swift
//  DOSBTSTests
//
//  Pure timing/threshold helpers for the hold-to-commit control (DMNC-796).
//

import Foundation
import SwiftUI
import Testing
@testable import DOSBTSApp

@Suite("HoldToCommitProgress helpers")
struct HoldToCommitProgressTests {

    private typealias Hold = HoldToCommitProgress<EmptyView>

    @Test("progress maps elapsed/duration clamped to 0...1")
    func progressClamping() {
        #expect(Hold.progress(elapsed: 0, duration: 0.8) == 0)
        #expect(Hold.progress(elapsed: 0.4, duration: 0.8) == 0.5)
        #expect(Hold.progress(elapsed: 0.8, duration: 0.8) == 1)
        #expect(Hold.progress(elapsed: 2.0, duration: 0.8) == 1)
        #expect(Hold.progress(elapsed: -1, duration: 0.8) == 0)
    }

    @Test("non-positive duration counts as full progress")
    func degenerateDuration() {
        #expect(Hold.progress(elapsed: 0, duration: 0) == 1)
        #expect(Hold.progress(elapsed: 0.5, duration: -1) == 1)
    }

    @Test("commit fires at or past the threshold, never before")
    func commitThreshold() {
        // Covers AE1: release at half the threshold must not commit.
        #expect(!Hold.shouldCommit(elapsed: 0.4, duration: 0.8))
        #expect(Hold.shouldCommit(elapsed: 0.8, duration: 0.8))
        #expect(Hold.shouldCommit(elapsed: 1.5, duration: 0.8))
    }

    @Test("tap immediately after a hold-commit is suppressed")
    func tapSuppressionInsideWindow() {
        let committed = Date()
        #expect(Hold.shouldSuppressTap(now: committed.addingTimeInterval(0.2), committedAt: committed))
    }

    @Test("tap after the suppression window passes through")
    func tapSuppressionOutsideWindow() {
        let committed = Date()
        #expect(!Hold.shouldSuppressTap(now: committed.addingTimeInterval(1.5), committedAt: committed))
    }

    @Test("tap at exactly the window edge passes through (strict <)")
    func tapSuppressionAtExactBoundary() {
        let committed = Date()
        #expect(!Hold.shouldSuppressTap(now: committed.addingTimeInterval(1.0), committedAt: committed))
    }

    @Test("tap with no prior commit passes through")
    func tapWithoutCommit() {
        #expect(!Hold.shouldSuppressTap(now: Date(), committedAt: nil))
    }

    @Test("hold duration is pinned — Reduce Motion step cadence derives from it")
    func holdDurationConstant() {
        #expect(Hold.holdDuration == 0.8)
    }

    @Test("fallback suppression window outlasts the hold threshold")
    func suppressionWindowExceedsHold() {
        // The wall-clock fallback only helps if it covers at least the time
        // between commit (at holdDuration) and a plausible release.
        let committed = Date()
        let justAfterThresholdRelease = committed.addingTimeInterval(Hold.holdDuration * 0.9)
        #expect(Hold.shouldSuppressTap(now: justAfterThresholdRelease, committedAt: committed))
    }
}

// MARK: - QuantityCommit (DMNC-1562)

@Suite("QuantityCommit")
struct QuantityCommitTests {

    private let id = UUID()
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("re-arm window boundary")
    func windowBoundary() {
        let last = (sourceKey: "gummy bear", entryID: id, at: t0)
        #expect(QuantityCommit.shouldEnterCountMode(lastLogged: last, tappedSourceKey: "gummy bear", now: t0.addingTimeInterval(14.9)))
        #expect(!QuantityCommit.shouldEnterCountMode(lastLogged: last, tappedSourceKey: "gummy bear", now: t0.addingTimeInterval(15.1)))
        #expect(!QuantityCommit.shouldEnterCountMode(lastLogged: nil, tappedSourceKey: "gummy bear", now: t0))
    }

    @Test("different source never enters count mode")
    func differentSource() {
        let last = (sourceKey: "gummy bear", entryID: id, at: t0)
        #expect(!QuantityCommit.shouldEnterCountMode(lastLogged: last, tappedSourceKey: "milk", now: t0.addingTimeInterval(1)))
    }

    @Test("sourceKey trims and lowercases")
    func sourceKey() {
        #expect(QuantityCommit.sourceKey(for: "  Gummy Bear ") == "gummy bear")
    }

    @Test("scaling multiplies macros, nil stays nil, identity preserved")
    func scalingMath() {
        let session = UUID()
        let base = MealEntry(id: id, timestamp: t0, mealDescription: "Gummy bear", carbsGrams: 3, proteinGrams: nil, fatGrams: 0.5, calories: 10, fiberGrams: nil, analysisSessionId: session)
        let s = QuantityCommit.scaled(base, count: 15)
        #expect(s.id == base.id)
        #expect(s.timestamp == base.timestamp)
        #expect(s.analysisSessionId == session)
        #expect(s.mealDescription == "15× Gummy bear")
        #expect(s.carbsGrams == 45)
        #expect(s.proteinGrams == nil)
        #expect(s.fatGrams == 7.5)
        #expect(s.calories == 150)
        #expect(s.fiberGrams == nil)
    }

    @Test("scaled description is refused as a base")
    func scaledRefusedAsBase() {
        #expect(QuantityCommit.isScaledDescription("3× Gummy bear"))
        #expect(!QuantityCommit.isScaledDescription("Gummy bear"))
        let last = (sourceKey: "3× gummy bear", entryID: id, at: t0)
        #expect(!QuantityCommit.shouldEnterCountMode(lastLogged: last, tappedSourceKey: "3× gummy bear", now: t0.addingTimeInterval(1)))
    }

    @Test("hypo sources never enter count mode")
    func hypoRefused() {
        let last = (sourceKey: "juice", entryID: id, at: t0)
        #expect(!QuantityCommit.shouldEnterCountMode(lastLogged: last, tappedSourceKey: "juice", now: t0.addingTimeInterval(1), hypoSourceKeys: ["juice"]))
    }

    @Test("scaled does not strip an existing prefix")
    func scaledDoesNotStrip() {
        let base = MealEntry(id: id, timestamp: t0, mealDescription: "3× Gummy bear", carbsGrams: 2)
        #expect(QuantityCommit.scaled(base, count: 5).mealDescription == "5× 3× Gummy bear")
    }

    @Test("count clamps to 2...99")
    func clamping() {
        let base = MealEntry(id: id, timestamp: t0, mealDescription: "Gummy bear", carbsGrams: 1)
        #expect(QuantityCommit.scaled(base, count: 500).mealDescription == "99× Gummy bear")
        #expect(QuantityCommit.scaled(base, count: 500).carbsGrams == 99)
        #expect(QuantityCommit.scaled(base, count: 0).mealDescription == "2× Gummy bear")
        #expect(QuantityCommit.scaled(base, count: 1).carbsGrams == 2)
    }
}
