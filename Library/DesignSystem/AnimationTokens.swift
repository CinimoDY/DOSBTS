//
//  AnimationTokens.swift
//  DOSBTS
//
//  Standard motion tokens for the DOS amber design system.
//

import SwiftUI

/// Standard motion tokens consumed across the app's animated surfaces.
///
/// Reduce-motion: pass `reduceMotion` from `@Environment(\.accessibilityReduceMotion)`
/// to `adapted(spring:reduceMotion:)` — it degrades any spring to a short linear fade.
public enum AnimationTokens {

    // MARK: - Springs

    /// General-purpose spring: card reveals, sheet transitions.
    public static let normal = Animation.spring(response: 0.4, dampingFraction: 0.7)

    /// Snappy spring: interactive feedback, quick state changes.
    public static let snappy = Animation.spring(response: 0.25, dampingFraction: 0.8)

    // MARK: - Durations

    /// 0.15 s — icon swap, immediate feedback
    public static let durationShort: Double = 0.15

    /// 0.25 s — standard cross-fade
    public static let durationMedium: Double = 0.25

    /// 0.4 s — enter/exit transitions
    public static let durationLong: Double = 0.4

    // MARK: - Pulse

    /// ~1.2 s breathing loop for loading/attention pulses (rationalizes 0.8/1.2/1.4 singletons)
    public static let durationPulse: Double = 1.2
    public static let pulse = Animation.easeInOut(duration: durationPulse).repeatForever(autoreverses: true)

    // MARK: - Eases

    /// Standard cross-fade easing.
    public static let easeStandard = Animation.easeInOut(duration: durationMedium)

    /// Exit easing: fast-out.
    public static let easeExit = Animation.easeIn(duration: durationShort)

    // MARK: - Reduce-motion adaptation

    /// Returns `spring` unchanged when `reduceMotion` is false; degrades to a
    /// short linear animation when the user has requested reduced motion.
    public static func adapted(spring: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: durationShort) : spring
    }

    /// Returns `animation` unchanged when `reduceMotion` is false; returns nil
    /// (no animation) when the user has requested reduced motion.
    public static func adapted(animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}
