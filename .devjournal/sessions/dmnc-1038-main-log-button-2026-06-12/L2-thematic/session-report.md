# Session Report — DMNC-1038 Main log button inconsistency

**Date:** 2026-06-12
**Branch:** claude/dmnc-1038
**Commit:** 71c33613

## What Was Done

**Fixed the INSULIN/MEAL bar on Log and Settings tabs** — the buttons were
hidden behind the native tab bar on iOS 26 after PR #54 switched from
`tabViewBottomAccessory` to per-tab `safeAreaInset`.

## Root Cause

PR #54 applied `safeAreaInset(edge: .bottom) { GlucoseStatusBar() }` to the
outer `VStack` in `GlucoseFramedTab`. That VStack contains `GlucoseTopBar` +
a `NavigationStack`. On iOS 26, a `NavigationStack` placed inside a `VStack`
renders at a higher Z-level than the `VStack`'s `safeAreaInset` content — the
bar was laid out correctly (it had the right vertical position) but the
NavigationStack's rendering stack covered it visually.

The issue did not manifest on Overview (plain VStack, no NavigationStack inside)
or Digest (ScrollView host, no NavigationStack inside), which is why it appeared
as an "inconsistency" rather than a global regression.

## Fix

One-line change in `GlucoseFramedTab`: move `safeAreaInset(.bottom)` from the
outer VStack to `content()` (the NavigationStack itself). This puts
GlucoseStatusBar inside the NavigationStack's own layer so it renders above list
content and persists correctly through navigation pushes.

```swift
// Before
VStack(spacing: 0) {
    GlucoseTopBar()
    content()
}
.background(AmberTheme.dosBlack)
.safeAreaInset(edge: .bottom, spacing: 0) { GlucoseStatusBar() }

// After
VStack(spacing: 0) {
    GlucoseTopBar()
    content()
        .safeAreaInset(edge: .bottom, spacing: 0) { GlucoseStatusBar() }
}
.background(AmberTheme.dosBlack)
```

## Code Review Notes

The `/code-review` pass surfaced two findings:

1. **Behavioral change — bar on pushed sub-screens**: With the inset now on the
   NavigationStack, GlucoseStatusBar persists through push/pop transitions and
   appears on Settings category sub-screens. This matches the intent (CLAUDE.md:
   "persistent", and the original `tabViewBottomAccessory` also appeared on all
   sub-screens). Not a bug.

2. **Implicit contract**: `GlucoseFramedTab<Content: View>` doesn't enforce that
   `content()` returns a NavigationStack, but the fix only works correctly when it
   does. Both current callers (ListsView, SettingsView) pass NavigationStack.
   The doc comment already says "Used by the NavigationStack-rooted tabs" — no
   further change warranted for this isolated fix.

## Tests

335 tests passed, 0 failed. No new tests were added (the fix is a view-layer
layout change; existing tests cover the display model and state logic).

## Files Changed

- `App/Views/SharedViews/GlucoseStatusBar.swift` — moved safeAreaInset
- `CHANGELOG.md` — added Fixed entry
