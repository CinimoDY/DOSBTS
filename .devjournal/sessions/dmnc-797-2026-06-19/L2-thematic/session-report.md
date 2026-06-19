## Session Report — DMNC-797

**Date:** 2026-06-19
**Branch:** claude/dmnc-797
**Duration:** Full implementation session — new AnimationTokens system + FiguresLoadingView + migrations + code review fixes

### What Was Done

- **AnimationTokens** (`Library/DesignSystem/AnimationTokens.swift`) — new motion token enum: `normal` spring (0.4/0.7), `snappy` spring (0.25/0.8), three durations (0.15/0.25/0.4 s), `easeStandard` / `easeExit`, and two reduce-motion adapters. Placed alongside AmberTheme/DOSTypography/DOSSpacing in the shared design system.
- **FiguresLoadingView** (`App/Views/SharedViews/FiguresLoadingView.swift`) — three pulsing amber dots via `TimelineView(.animation)` + `Canvas`; sin-based staggered oscillation (0.35 s phase offset per dot, 2.2 Hz). Under reduce-motion: static dots at 60% opacity. Wrapped in `.accessibilityHidden(true)` — surrounding text on all three call sites owns the VoiceOver label.
- **FoodPhotoAnalysisView** — replaced `ProgressView` with `FiguresLoadingView(dotSize: 10, spacing: 7)`; phase-cycling text animation upgraded to `AnimationTokens.adapted(animation:reduceMotion:)` so it suppresses under reduce-motion; haptic `.success` fires on analysis completion (result non-nil, loading false→false transition guard).
- **DigestView** — added `FiguresLoadingView` to loading card with `DOSSpacing.md` gap; haptic `.light` fires when digest loads.
- **SensorLineView** — added `FiguresLoadingView(dotSize: 5, spacing: 3, color: AmberTheme.amberLight)` in the transient state (connecting/scanning/pairing); haptic `.success` fires on `.connected`.
- **AnimationTokensTests** — 6 Swift Testing tests (smoke-test reduce-motion adapters, verify duration ordering, verify spring tokens are distinct). Manually registered in pbxproj (4 entries — tests are not fileSystemSynchronized).
- **Code review findings fixed:** (1) staticDots height matched to animated Canvas height (both `dotSize * 2`) to prevent layout jump; (2) FoodPhotoAnalysisView animation now respects reduceMotion; (3) accessibility hidden added to FiguresLoadingView.
- **CHANGELOG** — `## [Unreleased]` entry added under `Added`.
- **docs/design-system.md** — "Motion & Animation" section added documenting AnimationTokens table and FiguresLoadingView usage.

### Commits

| Hash | Message |
|------|---------|
| fd2171a3 | feat(ux): micro-interactions foundation — AnimationTokens + figures loading (DMNC-797) |
| 4e302e56 | fix(ux): address code review findings in FiguresLoadingView + FoodPhotoAnalysisView (DMNC-797) |

### Key Decisions

- **Canvas height = dotSize * 2**: gives the dot room to scale up to 1.0× without clipping; matches static branch height for stable layouts.
- **accessibilityHidden on the whole view**: Canvas is invisible to VoiceOver anyway; all three call sites have textual surroundings that describe the loading state. Adding a semantic role to compete with surrounding text would confuse the VoiceOver reading order.
- **Haptic on sensor connect fires on every BLE reconnect** (no cooldown): accepted. Automatic reconnects are infrequent and each is a meaningful user-observable state change (glucose readings resume). Not a regression — previously there was no haptic at all.

### Issues Updated

- DMNC-797 — Done (PR #61 draft open)

### Open PRs

- [PR #61](https://github.com/CinimoDY/DOSBTS/pull/61) (draft) — feat(ux): micro-interactions foundation — AnimationTokens + FiguresLoadingView (DMNC-797)

### Documentation Status

- CLAUDE.md: no change needed
- design-system.md: updated (Motion & Animation section)
- CHANGELOG.md: updated
- Compound: `docs/solutions/ui-bugs/swiftui-viewbuilder-branch-height-mismatch-layout-jump.md` (new)
- Memory: no new entries warranted
