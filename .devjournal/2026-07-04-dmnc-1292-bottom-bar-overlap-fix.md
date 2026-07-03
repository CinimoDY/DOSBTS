# DMNC-1292 — Bottom bar overlap fix

## What changed

Three files, two root causes fixed.

### Root cause 1 — transparent bar container (`GlucoseStatusBar.swift`)

`GlucoseStatusBar.body` had no background on its outer `VStack`. Only the inner
`HStack` was explicitly black, leaving the Divider row and any layout gap
between transparent. List content visually showed through when scrolled to the
bottom. Fix: add `.background(AmberTheme.dosBlack)` to the outer `VStack` and
remove the now-redundant inner `HStack` background.

While here, also fixed a pre-existing visual bug: `Divider().background(...)` 
doesn't colour the separator line itself (SwiftUI Divider draws in system
separator colour regardless). Replaced with `Rectangle().fill(AmberTheme.dosBorder)
.frame(height: 1)`, matching the `GlucoseTopBar` pattern.

### Root cause 2 — safeAreaInset outside the NavigationStack (`GlucoseStatusBar.swift` + `ListsView.swift` + `SettingsView.swift`)

`GlucoseFramedTab` was applying `safeAreaInset(edge: .bottom)` to the
`NavigationStack` from the **outside**. Pushed destination views (Settings
category screens, CalibrationsView, Log detail screens) live in their own view
controller context within the NavigationStack and don't inherit an inset applied
to the stack's host. Their last rows scrolled under the bar.

Fix: moved the `NavigationStack` ownership **into** `GlucoseFramedTab`, applied
`safeAreaInset` to `content()` **inside** the NavigationStack. SwiftUI
propagates an inner-stack safe area through all destination views via the
UINavigationController's additional safe area insets, so root and pushed views
both clear the bar.

`ListsView` and `SettingsView` updated to pass the root `List` directly (no
`NavigationStack` wrapper) since `GlucoseFramedTab` now provides it.

## What stayed the same

- `OverviewView` mounts its own `GlucoseStatusBar` directly via
  `safeAreaInset(edge: .bottom)` — not touched (documented GeometryReader
  subtlety in docs/solutions/ui-bugs/swiftui-vstack-overflow-sinks-safeareainset.md).
- `DigestView` mounts `GlucoseTopBar` and `GlucoseStatusBar` directly — not
  touched (plain ScrollView, no NavigationStack subtlety).

## Review findings addressed

Code review (high-effort workflow) surfaced 3 survivors:
- [0] Divider colour bug — fixed (Rectangle replacement)
- [1] NavigationStack contract enforced only by doc comment — accepted, no
  compile-time solution available without complex type gymnastics
- [2] Redundant inner HStack background — fixed (removed)
