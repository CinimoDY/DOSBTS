---
date: 2026-07-02
issue: DMNC-1217
title: DOS progress indicator, empty/error state views, button unification (WP-D)
tags: [design-system, ux, components, buttons]
---

## What changed

Eliminated all traces of system-chrome UI vocabulary from the app: bare `ProgressView()` spinners are gone, `.borderedProminent` buttons are gone, and empty/error states now speak from two shared components rather than bespoke inline VStacks.

### FiguresLoadingView.inline preset

Added an `inline` static property to `FiguresLoadingView` — a `FiguresLoadingView(dotSize: 8, spacing: 6)` preset that's the drop-in replacement for any bare `ProgressView()`. Replaced six call sites:

| File | Context |
|---|---|
| `ItemBarcodeScannerView.swift` | Product lookup overlay on camera feed |
| `HealthImportSourcesView.swift` | Source-list loading row in Apple Health import |
| `BarcodeScannerView.swift` | Product lookup overlay (barcode → OFF → staging plate) |
| `FoodPhotoAnalysisView.swift` | Inline "Updating estimate..." during AI follow-up |
| `TreatmentBannerView.swift` | "RECHECKING..." state in the hypo treatment banner |
| `UnifiedFoodEntryView.swift` | "Analyzing..." row in the ASK AI section of Log Meal |

Determinate `ProgressView(value:)` is unchanged — the ban is on the indeterminate spinner form only.

### DOSStateViews.swift — new shared components

Created `App/Views/SharedViews/DOSStateViews.swift` with two views:

- **`DOSEmptyState`** — `bodyLarge` amber title + optional `caption` amberDark detail + optional `.dosGhost` action button. Used when a data set is genuinely empty.
- **`DOSErrorState`** — `caption` cgaRed message + optional `.dosGhost` RETRY button. Used when an operation fails.

Adoption sites:
- `DigestView.noDataView` → `DOSEmptyState(title: "NO DATA FOR THIS DAY")`
- `BarcodeScannerView.errorView` → `DOSErrorState(message:retry:)` — the existing inline Cancel was already redundant with the toolbar Cancel, so it was removed from the body
- `ItemBarcodeScannerView` error branch → `DOSErrorState(message:retry:)` — same Cancel redundancy removed
- `UnifiedFoodEntryView` "NO HYPO TREATMENTS CONFIGURED" section → `DOSEmptyState(title:detail:)` with a hint to use Favorites

### DOSButtonStyle sugar

Added convenience extensions to `DOSButtonStyle.swift`:

```swift
.buttonStyle(.dosPrimary)  // amber fill, dosBlack ink
.buttonStyle(.dosGhost)    // clear fill, amber text
```

Replaced both `.borderedProminent` buttons:
- `FoodPhotoAnalysisView.swift` — "Set Up AI Analysis" consent prompt
- `AIConsentView.swift` — "Allow Food Photo Analysis" confirm button

The `.tint(AmberTheme.amber)` modifier that accompanied `.borderedProminent` was removed (DOSButtonStyle handles its own appearance).

### NumberSelectorView — deliberate exception

The two `.borderless` stepper buttons (±) in `NumberSelectorView.swift` were verified as a necessary exception: `.borderless` prevents the entire List row from capturing the tap, which matters since both buttons share a row with a Slider. Their labels already use DOSTypography + AmberTheme tokens. Tracked for WP-I.

### Docs + CHANGELOG

- `docs/design-system.md`: expanded Buttons section ("DOSButtonStyle only; `.dosPrimary`/`.dosGhost` sugar"); added "State views + progress" subsection documenting both `DOSEmptyState`/`DOSErrorState` APIs and the `.inline` preset rule.
- `CHANGELOG.md [Unreleased]`: two entries — spinners replaced, AI consent/analyze buttons changed.

## Why this matters

Every `ProgressView()` rendered the system spinner in white/gray — visually inconsistent with the DOS phosphor vocabulary and missing reduce-motion + low-power cadence handling that `FiguresLoadingView` provides. The `.borderedProminent` buttons rendered with iOS system blue chrome, breaking the dark-only amber aesthetic. Both were visible departures that accumulated across the AI/barcode features built in parallel without a unified loading/state vocabulary to draw from.

## What wasn't changed

- `ProgressView(value:)` deterministic bars — semantically distinct, kept
- `FiguresLoadingView` existing usages (sensor warmup, digest loading) — already correct
- `NumberSelectorView` `.borderless` stepper buttons — deliberate exception (see above)
- `FoodPhotoAnalysisView.errorSection` — kept as an inline bespoke VStack; the form layout (Section wrapping, icon, body-size text) doesn't map cleanly to `DOSErrorState`'s caption-size vocabulary
