# DMNC-1167: Tab bar unselected item tint under iOS 26 Liquid Glass

**Date:** 2026-06-25
**Branch:** claude/dmnc-1167
**PR:** _TBD_
**Planning issue:** DMNC-1029 — plan at `docs/plans/2026-06-21-dmnc-1029-plan.md`

## Goal

Unselected tab labels/icons render system white/gray under the iOS 26 Liquid Glass
tab bar — the last "real white" after the CGA pass. The plan's Option A was to set
the **granular** per-state `UITabBarItemAppearance` colors (which the convenience
`unselectedItemTintColor` proxy supposedly couldn't reach under the glass), making
unselected items dim `amberDark` and selected bright `amber`.

## Outcome: platform-constrained (Option D), not fixed

Implemented Option A exactly as planned, then ran the load-bearing verification gate
on iPhone 17 Pro / iOS 26.5. **The granular API is also ignored.** Two diagnostic
builds nailed down *why*:

1. Set `.normal` icon/title to **cyan** and the bar `backgroundColor` to **blue**,
   installed via `UITabBar.appearance()` in `ContentView.onAppear` → no on-screen
   change (still dark glass, white unselected items).
2. Moved the same install into `App.init()` (before the TabView's bar is created, to
   rule out the "appearance only affects subsequently-created bars" timing rule) →
   still no change.

Conclusion: **iOS 26's SwiftUI `TabView` Liquid Glass bar ignores
`UITabBar.appearance()` entirely** — convenience tint, granular item appearance, AND
`backgroundColor`. The selected tab is amber only because of SwiftUI's root
`.tint(AmberTheme.amber)` (App.swift), not the proxy. There is no SwiftUI-native
unselected-item color API (the plan's Option B confirmed this). "De-glassing"
(Option C) would rely on the same ignored proxy. Per the task's explicit guidance —
*"fall back per Options B–D and document the outcome rather than fighting the glass"* —
this lands on Option D: accept the system-controlled unselected color and document.

## What changed

### `App/DesignSystem/DOSTabBarAppearance.swift` (new)

Pure factory `make() -> UITabBarAppearance` setting `.normal` → `amberDark` and
`.selected` → `amber` (icon + title) on all three layout appearances (stacked /
inline / compact), opaque black background. Retained as the **correct,
forward-compatible** UIKit configuration (matches the nav-bar appearance pattern) —
honestly documented as **currently inert** under the iOS 26 SwiftUI TabView, kept in
case a future point release honors the proxy or a UIKit-backed surface consumes it.

### `App/Views/ContentView.swift`

Second `onAppear` now consumes `DOSTabBarAppearance.make()` instead of building the
appearance inline (KTD-2 readability). The legacy convenience `unselectedItemTintColor`
/ `tintColor` setters were **dropped** (code-review finding): the plan's KTD-1 kept
them as belt-and-braces for "older / non-glass" surfaces, but the deployment target is
iOS-26-only and both mechanisms are equally inert, so they only duplicated the
factory's token→state mapping. The factory is now the single source. Comment rewritten
to state the empirical no-op finding plainly rather than claiming a working fix.

### `DOSBTSTests/DOSTabBarAppearanceTests.swift` (new) + `project.pbxproj`

Three Swift Testing cases pinning the factory's token→state mapping (normal =
amberDark, selected = amber, all three layouts). This pins the *configuration*
invariant, not the on-screen result (the build-and-observe gate covers that). Wired
into the `DOSBTSTests` group + `PBXSourcesBuildPhase` manually (tests aren't
file-system-synchronized) — IDs `TE01000{1,2}0000002200A00022`.

### `docs/solutions/best-practices/ios-26-liquid-glass-theming-gotchas.md`

Added gotcha **#4**: the full empirical finding, so the next person doesn't
re-discover it. Updated frontmatter (`applies_when`, tags), "Why This Matters", and
"When to Apply".

### CHANGELOG

No entry — this is **not** a user-visible fix (unselected tabs still render
system-colored). Per CLAUDE.md, an internal investigation/inert config needs no
changelog line. (Added one during implementation, removed it once the gate failed.)

## Why keep the inert code instead of reverting?

The merged plan (PR #67) explicitly chose KTD-1 (keep the appearance config) and
KTD-2 (extract a testable factory). The config is the *correct* most-specific UIKit
appearance and is zero-risk; Apple's iOS 26 glass behavior is undocumented and has
shifted across point releases. Keeping it (clearly labeled inert) + the token pin
honors the plan and leaves a clean home should the platform start honoring it. The
durable deliverable is the learning-doc entry.

## Verification

- `xcodebuild ... DOSBTSApp ... build` → **BUILD SUCCEEDED**.
- `DOSTabBarAppearanceTests` (3 cases) → **all pass**.
- On-device gate: screenshots on iPhone 17 Pro / iOS 26.5 confirm selected = amber,
  unselected = system white (the platform constraint). Diagnostic builds documented
  above.

## Recommendation

Close DMNC-1029 as platform-constrained (won't-fix on the recolor; knowledge
captured). A true recolor would require a fully custom (non-`UITabBar`) tab bar —
out of scope for the skin.
