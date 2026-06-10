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
