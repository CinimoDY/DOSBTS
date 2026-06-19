---
title: "SwiftUI @ViewBuilder if/else branches with different heights cause layout jump on condition change"
date: 2026-06-19
category: ui-bugs
module: App/Views/SharedViews/FiguresLoadingView
problem_type: ui_bug
component: frontend_stimulus
symptoms:
  - "View snaps to a different height when reduceMotion toggles at runtime"
  - "Layout jumps abruptly without animation when an @Environment value changes and the view renders a different branch"
root_cause: implementation_bug
resolution_type: code_fix
severity: minor
tags: [swiftui, layout, viewbuilder, reduce-motion, animation, accessibility]
---

# SwiftUI @ViewBuilder if/else branches with different heights cause layout jump on condition change

## Problem

When a SwiftUI `body` or `@ViewBuilder` closure switches between two branches via `if`/`else`, SwiftUI measures each branch's intrinsic size independently. If the branches produce different heights (or widths), the parent layout changes dimensions when the condition switches, causing a visible snap even inside a `withAnimation` block.

## Symptoms

- A view resizes abruptly when an `@Environment` value (e.g., `accessibilityReduceMotion`, `colorScheme`, `dynamicTypeSize`) changes.
- The jump occurs even when the parent wraps the state change in `withAnimation`.
- Only one dimension jumps; the other (the constrained axis) may be unaffected.

## What Didn't Work

Using a plain `if reduceMotion { staticBranch } else { animatedBranch }` without equalising heights. The static branch (`HStack` of circles with `frame(width: dotSize, height: dotSize)`) was `dotSize` tall; the animated branch (Canvas with `.frame(height: dotSize * 2)`) was twice as tall. Toggling `reduceMotion` switched between these sizes and produced a visible layout jump.

## Solution

Add an explicit `.frame(height:)` to the shorter branch so both branches report the same height to their parent:

```swift
// Before — branches have different heights → layout jump
var body: some View {
    if reduceMotion {
        HStack { /* circles */ }          // dotSize tall
    } else {
        TimelineView(.animation) { ... }
            .frame(height: dotSize * 2)   // dotSize * 2 tall ← MISMATCH
    }
}

// After — wrap in Group, equalize heights → no jump
var body: some View {
    Group {
        if reduceMotion {
            HStack { /* circles */ }
                .frame(height: dotSize * 2)  // ← matches animated branch
        } else {
            TimelineView(.animation) { ... }
                .frame(height: dotSize * 2)
        }
    }
    .accessibilityHidden(true)
}
```

The `Group` wrapper is not required for the fix itself (the `.frame` on the static branch is the fix), but it lets `.accessibilityHidden(true)` and other modifiers apply to both branches from a single call site.

## Why This Works

SwiftUI's layout system measures each branch of an `if/else` in isolation and stores the resulting size. When the condition toggles, the parent receives a new proposed size for the child and re-layouts. If the two sizes differ, the re-layout is visible as a jump regardless of whether the state change was animated — `withAnimation` animates the *transition between views*, not the *parent's dimension change*, which is immediate.

Equalising both branches to the same fixed height means the parent's allocated space is constant, so no re-layout occurs when the branch switches.

## Prevention

- When writing `if/else` inside a `@ViewBuilder` body, check that both branches produce the same intrinsic size on the relevant axis. If they differ, pin both branches to the larger size with `.frame`.
- If the branches genuinely need different sizes (e.g., a collapsed vs. expanded state), use an `.animation(.spring(), value: condition)` modifier on the outer frame and a single view that changes its content, rather than an `if/else` that replaces the whole view.
- For reduce-motion alternatives specifically: the reduce-motion branch is almost always the simpler/smaller version. Make it fill the same frame as the full-motion branch — it avoids both the layout jump and confusing reflows in the surrounding layout.

## Related Issues

- `DMNC-797` — AnimationTokens + FiguresLoadingView; this bug was caught in code review of the initial implementation.
