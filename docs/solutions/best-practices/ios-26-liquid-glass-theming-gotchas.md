---
title: iOS 26 Liquid Glass theming gotchas — nav titles, tabViewBottomAccessory, TabView wrapping, unselected tab item color
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
  - "Trying to recolor unselected tab bar items via UITabBar.appearance() on iOS 26"
tags: [ios-26, liquid-glass, tabviewbottomaccessory, uinavigationbar-appearance, uitabbar-appearance, safeareainset, theming]
---

# iOS 26 Liquid Glass theming gotchas — nav titles, tabViewBottomAccessory, TabView wrapping, unselected tab item color

## Context

The app-wide "no real white" CGA pass (builds 99–101) hit three iOS 26 platform behaviors that silently defeat custom theming; a fourth (the unselected tab bar item color, DMNC-1167) was added later. All were found empirically; documentation does not mention them.

## Guidance

1. **The SwiftUI nav bar ignores `UINavigationBar.appearance()` title attributes.** `titleTextAttributes` / `largeTitleTextAttributes` set in `onAppear` do nothing — titles stay system white. Background, shadow, and `tintColor` on the appearance still apply. Style visible titles with a **principal toolbar item** instead; this repo's `dosNavigationTitle` modifier (`App/DesignSystem/Modifiers/DOSModifiers.swift`) wraps that pattern and keeps `.navigationTitle` underneath for back-labels and VoiceOver.

2. **`tabViewBottomAccessory` fights custom theming twice.** (a) Buttons inside the accessory get wrapped in Liquid Glass tinted by the app's `.tint` — a custom ghost `ButtonStyle` is washed amber-on-amber; `.buttonStyle(.plain)` with hand-drawn chrome partially escapes it. (b) The capsule's rounded glass edges render *around* opaque content and become visible on lighter tab backgrounds — you cannot make the accessory look sharp-edged. The working fallback for a fully-themed persistent bar is a per-tab `safeAreaInset(edge: .bottom)` view (plain background, sharp edges); it also never minimizes, which a safety-critical bar wants anyway.

3. **A wrapper view around the TabView swallows the `tabViewBottomAccessory` preference.** With the TabView nested inside a `GeometryReader`/`ZStack` wrapper (the old LoadingView), the accessory never appears. The TabView must be the outermost view; full-screen overlays go in `.overlay { }` on the TabView instead.

4. **The iOS 26 SwiftUI TabView Liquid Glass bar ignores `UITabBar.appearance()` entirely — you cannot recolor unselected tab items.** Setting `standardAppearance` / `scrollEdgeAppearance` on the `UITabBar.appearance()` proxy has **no effect** on a SwiftUI `TabView` with `.tabItem` under iOS 26: not the convenience `unselectedItemTintColor`, not the granular per-state `UITabBarItemAppearance` (`stackedLayoutAppearance.normal/.selected .iconColor` + `.titleTextAttributes`), and not even `backgroundColor`. Verified empirically (DMNC-1167) with a diagnostic build using cyan unselected icons + a blue bar background, set both in `ContentView.onAppear` and in `App.init()` (before the bar is created) — the bar stayed the default dark glass with system-white unselected items in both cases. The **selected** tab tint is correct because it comes from SwiftUI's root `.tint(AmberTheme.amber)` (App.swift), *not* from the appearance proxy. There is **no SwiftUI-native API for the unselected tab item color** on any iOS version (`.tint` only drives the selected/accent color). Net: unselected tab labels/icons are locked to the system secondary color over the glass — the planned granular-appearance fix (DMNC-1029, Option A) is inert, and "de-glassing" the bar (Option C) would rely on the same ignored proxy. Treat unselected tab items as a platform-controlled, dimmed secondary affordance (the system's own unselected color is similarly low-contrast) rather than fighting the glass. The `DOSTabBarAppearance` factory + its install are retained as the correct, forward-compatible UIKit configuration (currently inert) and unit-pinned, not as a working recolor. The only route that would actually recolor unselected items is a fully custom (non-`UITabBar`) tab bar — large scope, out of scope for the skin.

## Why This Matters

All four failures are *silent* — no warnings, just default rendering. Each one cost an implement-run-observe loop to discover. A themed app on iOS 26 should reach for the principal-item title pattern and `safeAreaInset` bars first, treat the accessory API as suitable only for system-look content, and accept that unselected tab item colors are platform-controlled (only `.tint` for selected is honored).

## When to Apply

- Any nav-title restyling on iOS 26 → use `dosNavigationTitle` (or the principal-item pattern), never `UINavigationBar.appearance()` title attributes.
- Any persistent bottom bar that must carry the DOS skin → `safeAreaInset` per tab, not the accessory.
- Never wrap the root TabView in another container.
- Don't try to recolor unselected tab items via `UITabBar.appearance()` on iOS 26 — it's ignored. Style the selected state via SwiftUI `.tint`; accept the system unselected color, or commit to a fully custom tab bar.

## Examples

See `App/DesignSystem/Modifiers/DOSModifiers.swift` (title pattern), `App/Views/SharedViews/GlucoseStatusBar.swift` (`GlucoseFramedTab` + inset bar), `App/Views/ContentView.swift` (TabView-outermost + LoadingOverlay), and `App/DesignSystem/DOSTabBarAppearance.swift` (the inert-but-correct tab bar appearance factory, DMNC-1167).
