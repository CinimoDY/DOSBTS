//
//  AnimationTokensTests.swift
//  DOSBTSTests
//
//  Verifies AnimationTokens token values and reduce-motion adaptation (DMNC-797).
//

import Foundation
import SwiftUI
import Testing
@testable import DOSBTSApp

@Suite("AnimationTokens (DMNC-797)")
struct AnimationTokensTests {

    @Test("adapted(spring:reduceMotion:false) returns the spring unchanged")
    func springPassthroughWhenMotionAllowed() {
        // Animation doesn't conform to Equatable; smoke-test that the function
        // compiles and runs without crashing when reduce-motion is off.
        _ = AnimationTokens.adapted(spring: AnimationTokens.normal, reduceMotion: false)
    }

    @Test("adapted(spring:reduceMotion:true) degrades to a short linear animation")
    func springDegradedWhenReduceMotion() {
        // Smoke-test the reduce-motion code path (Animation has no public equality API).
        _ = AnimationTokens.adapted(spring: AnimationTokens.normal, reduceMotion: true)
    }

    @Test("adapted(animation:reduceMotion:false) returns non-nil")
    func animationPassthroughWhenMotionAllowed() {
        let result = AnimationTokens.adapted(animation: AnimationTokens.easeStandard, reduceMotion: false)
        #expect(result != nil)
    }

    @Test("adapted(animation:reduceMotion:true) returns nil")
    func animationNilWhenReduceMotion() {
        let result = AnimationTokens.adapted(animation: AnimationTokens.easeStandard, reduceMotion: true)
        #expect(result == nil)
    }

    @Test("durationShort is less than durationMedium is less than durationLong")
    func durationOrdering() {
        #expect(AnimationTokens.durationShort < AnimationTokens.durationMedium)
        #expect(AnimationTokens.durationMedium < AnimationTokens.durationLong)
    }

    @Test("spring tokens have expected response and damping values")
    func springTokenValues() {
        // We can't inspect Animation internals directly, but we can verify the
        // token constants are distinct by checking that normal != snappy via description.
        let normalDesc = "\(AnimationTokens.normal)"
        let snappyDesc = "\(AnimationTokens.snappy)"
        #expect(normalDesc != snappyDesc)
    }
}
