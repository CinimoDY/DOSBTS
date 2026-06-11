---
title: iOS 26 Liquid Glass theming gotchas — nav titles, tabViewBottomAccessory, TabView wrapping
date: 2026-06-11
category: best-practices
module: App/Views (ContentView, DOSModifiers, GlucoseStatusBar)
problem_type: best_practice
component: frontend_stimulus
severity: medium
applies_when:
  - "Styling navigation titles to non-system colors/fonts on iOS 26"
  - "Considering tabViewBottomAccessory for a custom-themed persistent bar"
  - "Restructuring ContentView around the root TabView"
tags: [ios-26, liquid-glass, tabviewbottomaccessory, uinavigationbar-appearance, safeareainset, theming]
---

# iOS 26 Liquid Glass theming gotchas — nav titles, tabViewBottomAccessory, TabView wrapping

## Context

The app-wide "no real white" CGA pass (builds 99–101) hit three iOS 26 platform behaviors that silently defeat custom theming. All three were found empirically; documentation does not mention them.

## Guidance

1. **The SwiftUI nav bar ignores `UINavigationBar.appearance()` title attributes.** `titleTextAttributes` / `largeTitleTextAttributes` set in `onAppear` do nothing — titles stay system white. Background, shadow, and `tintColor` on the appearance still apply. Style visible titles with a **principal toolbar item** instead; this repo's `dosNavigationTitle` modifier (`App/DesignSystem/Modifiers/DOSModifiers.swift`) wraps that pattern and keeps `.navigationTitle` underneath for back-labels and VoiceOver.

2. **`tabViewBottomAccessory` fights custom theming twice.** (a) Buttons inside the accessory get wrapped in Liquid Glass tinted by the app's `.tint` — a custom ghost `ButtonStyle` is washed amber-on-amber; `.buttonStyle(.plain)` with hand-drawn chrome partially escapes it. (b) The capsule's rounded glass edges render *around* opaque content and become visible on lighter tab backgrounds — you cannot make the accessory look sharp-edged. The working fallback for a fully-themed persistent bar is a per-tab `safeAreaInset(edge: .bottom)` view (plain background, sharp edges); it also never minimizes, which a safety-critical bar wants anyway.

3. **A wrapper view around the TabView swallows the `tabViewBottomAccessory` preference.** With the TabView nested inside a `GeometryReader`/`ZStack` wrapper (the old LoadingView), the accessory never appears. The TabView must be the outermost view; full-screen overlays go in `.overlay { }` on the TabView instead.

## Why This Matters

All three failures are *silent* — no warnings, just default rendering. Each one cost an implement-run-observe loop to discover. A themed app on iOS 26 should reach for the principal-item title pattern and `safeAreaInset` bars first, and treat the accessory API as suitable only for system-look content.

## When to Apply

- Any nav-title restyling on iOS 26 → use `dosNavigationTitle` (or the principal-item pattern), never `UINavigationBar.appearance()` title attributes.
- Any persistent bottom bar that must carry the DOS skin → `safeAreaInset` per tab, not the accessory.
- Never wrap the root TabView in another container.

## Examples

See `App/DesignSystem/Modifiers/DOSModifiers.swift` (title pattern), `App/Views/SharedViews/GlucoseStatusBar.swift` (`GlucoseFramedTab` + inset bar), and `App/Views/ContentView.swift` (TabView-outermost + LoadingOverlay).
