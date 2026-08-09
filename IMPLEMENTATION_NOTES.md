# Implementation notes — Sensor chip overlap + Digest colour parity (DMNC-1481)

Newest entry on top. This file exists to feed the PR body and is removed before the branch's
final commit (per executor protocol — a root-level file added by every parallel worker branch
guarantees an N-way merge conflict).

---

## Deviation: GeometryReader attachment point (Part 1, step 2)

The plan's code snippet says to attach `.background(GeometryReader { ... })` to "the `HStack`
wrapping `trailingContent` at `:30-33`" — i.e. `HStack { Spacer(); trailingContent }`. I attached
it to `trailingContent` itself instead (nested one level deeper, inside that HStack), not to the
HStack as a whole.

**Why:** that HStack contains a `Spacer()`, which in SwiftUI absorbs all width the parent proposes
to the HStack. Since the ZStack proposes its own (large, concrete) content width to both children,
`HStack { Spacer(); trailingContent }` always sizes itself to that full width — a `GeometryReader`
backing the *whole HStack* would therefore always report ~370pt (the full row), never the chip's
own ~96/74/67pt, regardless of which chip is showing or whether one is showing at all. That
contradicts:
- the plan's own arithmetic table, which expects the measured value to equal the chip's own
  text+padding total (96.0 / 74.4 / 67.2), not the row width;
- the plan's stated reason for adding `.fixedSize()` to the three chip labels — "so the measured
  width is the chip's intrinsic width and cannot itself be compressed by the parent" — which only
  matters if the measurement target is the chip itself;
- the plan's "Known-acceptable" note describing a transient 0-to-chip-width lag on reveal/hide,
  which only makes sense if the measured value tracks the chip (present vs absent), not the
  ever-full HStack.

Attaching to `trailingContent` directly makes all three of those true: the GeometryReader reports
the chip's own rendered size (0 for `EmptyView()` when no chip renders, ~96/74/67 when one does),
`.fixedSize()` on the labels is what guarantees that reported size is the label's true intrinsic
width rather than whatever the HStack would otherwise compress it to, and the reveal/hide lag
described as "known-acceptable" is real and observable (one frame at the `DOSSpacing.md` floor
before the true measurement lands).

No functional code differs from what the plan asks for beyond this one attachment point — the
`ChipWidthKey` definition, the `@State`/`.onPreferenceChange` wiring, the `max(measuredChipWidth,
DOSSpacing.md)` padding expression, and the three `.fixedSize()` additions all match the plan
verbatim.

## Factual correction: DOSTypography.caption does not visibly scale with Dynamic Type

The plan's "why a constant cannot be the fix" section states: "`DOSTypography.caption` is
`Font.system(size: 12, …)` … so it scales with Dynamic Type … At accessibility sizes the chip is
2.5–3× wider." I tested this empirically on the assigned simulator: `xcrun simctl ui <UDID>
content_size extra-extra-extra-large`, both live and via a full `terminate`+`launch` (to rule out
a live-propagation timing issue), produced **zero visible change** in the rendered chip/label text
size (screenshots `02-disconnected-xxxlarge.png` / `03-disconnected-xxxlarge-relaunch.png` are
pixel-for-pixel the same size as the baseline `01-fresh-launch.png`).

This matches standard SwiftUI behavior: `Font.system(size:weight:design:)` with an explicit point
size does not auto-scale with Dynamic Type — only semantic text styles (`.system(.body)`) or
`Font.custom(_:size:relativeTo:)` do. Every member of `DOSTypography` (not just `.caption`) is
defined via the fixed-size `Font.system(size:weight:design:)` form, so this appears to be an
app-wide characteristic, not specific to the sensor chip.

**This does not change the implementation.** The measured-width fix is still the correct approach
regardless of whether Dynamic Type is the specific mechanism that varies chip width — a hard-coded
constant still breaks under localization (a translated "DISCONNECT" won't be the same length) or
any future copy/typography change, which is the same underlying "don't hardcode a derived value"
argument the plan makes. Flagging this only so the plan's stated rationale isn't taken as verified
when it wasn't — worth a look if Dynamic Type support for DOSTypography is ever actually wanted
(it currently provides none, app-wide).

## Screenshot verification: partial, with reasons

Per the plan's verification section, 5 on-simulator checks were requested. Captured 1 of 5 as
literally specified, plus a variant of a 2nd; items 1, 2, 4, and 5 (as literally specified) were
not achievable in this session — details below. This is a tooling/environment gap, not a code gap:
`xcodebuild build` and `xcodebuild test` (the brief's actual hard gate) both passed in full.

**Captured:**
- Item 3 (disconnected / CONNECT chip, no overlap): `01-fresh-launch.png`. A genuinely fresh
  install (uninstall + install + launch, no seeding) lands in `.disconnected` with
  `hasSelectedConnection == true` (the simulator build defaults `selectedConnectionID` to
  `DirectConfig.virtualID` — see `AppState.init`), so the CONNECT chip renders unconditionally, no
  tap needed. "DISCONNECTED" and "CONNECT" render with a clean gap, no overlap.
- Item 2's underlying mechanism (not the literal xxxLarge-with-chip-revealed case, since that also
  needs a tap — see below): `02-disconnected-xxxlarge.png` / `03-disconnected-xxxlarge-relaunch.png`
  confirm no overlap regression at `content_size = extra-extra-extra-large`, though per the factual
  correction above this doesn't exercise a different rendered width than the baseline.

Worth noting: the CONNECT-chip screenshot is not a weaker consolation stand-in for the DISCONNECT
case — `reservesChipWidth` is unconditionally `true` for `.disconnected` (no reveal-gate, unlike
`.connected`), so it exercises the exact same `ChipWidthKey → measuredChipWidth → padding`
mechanism the DISCONNECT chip uses, just measuring a different 7-character label instead of a
10-character one. It's a direct functional proof of the new mechanism, just not of the specific
before/after overlap the DISCONNECT chip had (CONNECT was already fine before this fix — per the
plan's own table it was over-reserved by 11.6pt, never short).

**Not captured — items 1, 2 (as specified), 4, 5:** all four require an in-app tap
(`disconnectChipRevealed` is local SwiftUI `@State`, no UserDefaults/launch-arg path to it; the
Digest tab needs a tab-bar tap and `selectedView` isn't persisted; the registered `dosbts://` URL
scheme has zero `.onOpenURL` handlers anywhere in the codebase, confirmed by grep, so it's not a
deep-link shortcut either). No tap/gesture tool was available in this session: no `idb`/`fbsimctl`
on the machine, and the xcodebuild-mcp tap/gesture tool referenced by its own `snapshot_ui`
docstring ("use tap for one target") did not surface via tool search — only the read-only/lifecycle
subset of that MCP server was available.

I made one bounded attempt at OS-level clicking via `osascript`/System Events as a fallback (System
Events access was in fact permitted). Before clicking anything, I queried the frontmost
"Simulator" process window's bounds and screenshotted that exact region to confirm coordinates —
the capture showed an unrelated screen (a meal-entry flow with "Dextrose 15g", "MANUAL", "SCAN",
"RECENT"), i.e. **not my iPhone 16e Overview screen**. `Simulator.app` is one process hosting every
booted device's window, and System Events' "window 1" is frontmost-based, not scoped to a UDID —
there is no way to safely target only my simulator through it. Since the brief explicitly says
sibling workers own other simulators and never to touch theirs, I stopped immediately rather than
risk clicking into whichever sibling's window that was. All simulator interaction actually
performed was done exclusively through UDID-scoped `xcrun simctl` calls (`install`/`launch`/
`terminate`/`ui`/`io screenshot`), which are provably safe.

## Note (not a deviation): `EventMarkerTypeTests.swift` already exists

The plan directs the new color tests to `DOSBTSTests/SensorTests.swift`, reasoning that creating a
new test file "needs four manual `project.pbxproj` edits and buys nothing here." That reasoning is
correct, but `DOSBTSTests/EventMarkerTypeTests.swift` already exists and is already pbxproj-registered
— it has a `@Suite("InsulinType → EventMarkerType mapping")` that already pins
`InsulinType.markerType` for all four cases (just not `.color`). It's the more natural home for
this PR's color tests (same mapping, one field over) and would have needed no pbxproj edits either.
I followed the plan literally and added to `SensorTests.swift` as instructed rather than making an
organizational judgment call the plan didn't ask for. Flagging in case the orchestrator wants a
follow-up consolidation.

## Verification run (this session)

- `xcodebuild -project DOSBTS.xcodeproj -scheme DOSBTSApp -destination 'id=00C020D3-A83B-4E78-98F9-A9AA4AAE8673' -configuration Debug build` → `** BUILD SUCCEEDED **`
- `xcodebuild test -project DOSBTS.xcodeproj -scheme DOSBTSApp -destination 'id=00C020D3-A83B-4E78-98F9-A9AA4AAE8673'` → `** TEST SUCCEEDED **`, 689 passed / 0 failed across 114 suites, including all 9 `StyleGuardTests` rules + the sanity check, and the 8 new tests (`InsulinTypeMarkerColorTests` ×4, `EventMarkerTypeColorDistinctnessTests` ×4).
- Manual grep of every StyleGuard regex against both edited app-source files before the test run: zero hits on all 9 rules.
