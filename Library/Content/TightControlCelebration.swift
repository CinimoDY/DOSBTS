//
//  TightControlCelebration.swift
//  DOSBTS
//
//  Ephemeral display payload for a tight-control streak celebration (DMNC-772).
//  The middleware computes it and sets it on transient state; ContentView observes
//  the change and drives the toast (visual + VoiceOver always; sound + haptic only
//  when `withFeedback`). Not persisted.
//

import Foundation

struct TightControlCelebration: Equatable {
    /// Number of streaks this toast represents. 1 for a live/just-detected streak;
    /// N for a consolidated deferred drain.
    let count: Int
    /// Whole hours in range for a single live streak; nil for a consolidated (×N) or
    /// retroactively-drained celebration where individual durations aren't tracked.
    let hours: Int?
    /// Whether sound + haptic accompany the visual toast. False during night-profile
    /// hours (R10) — evaluated at presentation time by the middleware.
    let withFeedback: Bool
}
