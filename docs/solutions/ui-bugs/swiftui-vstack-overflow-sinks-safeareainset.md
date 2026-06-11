---
title: VStack with rigid children overflows the screen symmetrically and sinks safeAreaInset content behind the tab bar
date: 2026-06-11
category: ui-bugs
module: App/Views/OverviewView + App/Views/Overview/ChartView
problem_type: ui_bug
component: frontend_stimulus
symptoms:
  - "Bottom safeAreaInset buttons pushed behind the Liquid Glass tab bar when the treatment banner is inserted"
  - "Top content (hero glucose value) simultaneously clips upward by a few points — overflow is symmetric around center"
  - "Worse on shorter screens (iPhone 15 Pro vs 17 Pro)"
root_cause: logic_error
resolution_type: code_fix
severity: high
tags: [swiftui, vstack, overflow, safeareainset, geometryreader, uiscreen, fixed-height]
---

# VStack with rigid children overflows the screen symmetrically and sinks safeAreaInset content behind the tab bar

## Problem

Inserting the hypo-treatment countdown banner into Overview's VStack pushed the INSULIN/MEAL quick actions behind the tab bar. On the user's iPhone 15 Pro the buttons were unusable during a treatment cycle — exactly when they matter most.

## Symptoms

- With the banner active, the bottom `safeAreaInset` content sinks below/behind the tab bar; without it, layout is fine.
- The hero at the top moves UP a few points at the same time — the tell that the whole VStack is overflowing **symmetrically** (a VStack whose children's minimum heights exceed the proposal sizes to its content and centers in the frame, spilling both edges).

## What Didn't Work

- Adding bottom padding to the buttons: treats the symptom; the stack still overflows and the padding budget depends on device height.

## Solution

The rigid child was the chart: `height: min(UIScreen.screenHeight, Config.chartHeight)` — `screenHeight` is the full device height, so the min always resolved to the 250pt constant and the chart could never compress. Derive the height from the space actually available instead:

```swift
GeometryReader { chartAreaGeo in
    // ...
    glucoseChart.frame(width: ..., height: chartHeight(available: chartAreaGeo.size.height))
}

private func chartHeight(available: CGFloat) -> CGFloat {
    let forChart = available - Config.markerLaneHeight
    return max(Config.minChartHeight, min(Config.chartHeight, forChart))
}
```

When the banner appears, the GeometryReader's share shrinks and the chart absorbs the difference; the buttons never move.

## Why This Works

`safeAreaInset` pins its content to the bottom of the modified view's *frame*. When the VStack's content overflows the proposed frame, the frame's bottom edge effectively moves off-screen, taking the inset content with it. Making the flexible child genuinely compressible keeps the stack within its proposal under any combination of conditional rows.

## Prevention

- Never size a flexible-region child from `UIScreen` dimensions — `min(UIScreen.screenHeight, K)` is a constant in disguise. Use GeometryReader-available space.
- Diagnostic signature: if bottom-inset content sinks AND top content clips at the same time, the stack is overflowing — look for the rigid child, don't pad the symptom.
- Conditional rows (banners) inserted into full-height VStacks must be paired with at least one genuinely compressible sibling.

## Related Issues

- `App/Views/Overview/ChartView.swift` `chartHeight(available:)` — the implementation.
