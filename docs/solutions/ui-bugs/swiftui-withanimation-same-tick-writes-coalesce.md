---
title: Staged reveal never staggers — same-tick withAnimation writes to one @State coalesce into a single fade
date: 2026-06-11
category: ui-bugs
module: App/Views/DigestView (DigestInsightCard)
problem_type: ui_bug
component: frontend_stimulus
symptoms:
  - "A cascade built from a synchronous for-loop of withAnimation(.delay(i * step)) calls renders as one simultaneous fade instead of staggered stages"
root_cause: async_timing
resolution_type: code_fix
severity: low
tags: [swiftui, withanimation, animation-delay, staged-reveal, state-coalescing]
---

# Staged reveal never staggers — same-tick withAnimation writes to one @State coalesce into a single fade

## Problem

The digest insight card's CRT boot cascade (headline, then fact chips, then tips, then cheer) was written as a synchronous loop of delayed `withAnimation` calls. All blocks fade in together — the stagger never happens.

## Symptoms

- All stages appear in a single simultaneous fade despite per-stage `.delay(Double(stage) * 0.18)`.

## What Didn't Work

```swift
// Looks right, doesn't stagger: all four writes land in the same tick,
// SwiftUI coalesces them to the final value (4) in one transaction batch.
for stage in 0...3 {
    withAnimation(.easeOut(duration: 0.3).delay(Double(stage) * 0.18)) {
        revealedStages = stage + 1
    }
}
```

## Solution

Step the state asynchronously so each write lands in its own runloop tick:

```swift
Task { @MainActor in
    for stage in 0...3 {
        withAnimation(.easeOut(duration: 0.3)) { revealedStages = stage + 1 }
        try? await Task.sleep(for: .milliseconds(180))
    }
    withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
        cheerPulse = true
    }
}
```

Guard with `accessibilityReduceMotion` first (set everything to its final state, skip the Task).

## Why This Works

Multiple synchronous writes to the same `@State` in one tick coalesce — the body re-evaluates once with the final value, so intermediate stage values never render and the per-transaction delays cannot produce visible stagger. Sleeping between writes gives every stage its own render pass and its own animation transaction.

## Prevention

- For staged reveals driven by ONE state variable, use an async-stepped Task (or `PhaseAnimator` where it fits) — never a synchronous loop of delayed `withAnimation` calls.
- The delayed-withAnimation pattern is only sound when each call mutates a *different* state variable.

## Related Issues

- `App/Views/DigestView.swift` `DigestInsightCard.onAppear` — the corrected implementation.
