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

    /// Slow highlight fade (easeOut, 1.2 s — same cadence as durationPulse, one-shot).
    public static let highlightFade = Animation.easeOut(duration: durationPulse)

    /// Cursor / indicator blink (easeInOut, 0.4 s, repeat forever).
    public static let blink = Animation.easeInOut(duration: durationLong).repeatForever()

    // MARK: - Eases

    /// Standard cross-fade easing.
    public static let easeStandard = Animation.easeInOut(duration: durationMedium)

    /// Reveal easing: fast-start entry transitions (0.25 s easeOut).
    public static let easeReveal = Animation.easeOut(duration: durationMedium)

    /// Exit easing: fast-out.
    public static let easeExit = Animation.easeIn(duration: durationShort)

    /// Snap easing: quick element collapse or cancel (0.15 s easeOut).
    public static let easeSnap = Animation.easeOut(duration: durationShort)

    // MARK: - Gesture

    /// Linear fill for press-and-hold gestures; caller supplies the hold threshold.
    public static func gestureProgress(duration: TimeInterval) -> Animation {
        .linear(duration: duration)
    }

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
