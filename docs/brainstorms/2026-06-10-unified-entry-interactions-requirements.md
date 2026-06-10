---
date: 2026-06-10
topic: unified-entry-interactions
---

# Unified Entry Interactions (DMNC-796, re-grounded)

**Issue:** [DMNC-796](https://linear.app/lizomorf/issue/DMNC-796) (Medium)

## Summary

Ship the hybrid gesture vocabulary that DMNC-805 decided but never implemented: on every meal re-log surface, tap routes to the staging plate and press-and-hold insta-logs with a visible countdown loader. Alongside it, promote the toast to a shared component, migrate the QUICK favourites chip to an `AmberChip` variant, and adopt `StepperField` in blood glucose entry.

## Problem Frame

DMNC-796 was filed in April as the application layer for the OOUX patterns. Since then its siblings shipped most of its original scope: the shared primitives (DMNC-798), the AddInsulinView redesign (DMNC-799), the staging-plate decomposition (DMNC-800), recents tap-to-staging (DMNC-761), and chart-marker tap unification (DMNC-848). The Model A/B decision the issue agonises over was resolved in the OOUX doc's reversal log (2026-04-24, from TestFlight build 63 feedback).

What never landed is the decided behavior itself: `UnifiedFoodEntryView`'s favourite tap still direct-logs immediately with no review step, no hold-to-commit component exists, and the toast is locked inside one view. The gap between decided and shipped is this issue's remaining scope.

## Key Decisions

- **Hybrid gesture model (inherited from DMNC-805, not re-litigated).** Tap = staging plate, press-and-hold = insta-log with countdown loader. The loader is the confirmation — no hidden affordance, no accidental commit.
- **Hold gesture applies to favourites and recents.** One vocabulary everywhere a past meal can be re-logged. "Log again" survives as hold-on-recent.
- **Hypo-treatment favourites stay 1-tap direct log.** Staging during a hypo event is wrong (shaky hands, urgency, treatment safety). This is the reserved "quick add" area the issue asked to clarify.
- **Expand-from-tag dropped.** It predates the staging-plate routing decision; favourites/recents already render as visible rows and the plate covers review. No second selection layer.
- **Fixed hold duration, Reduce Motion respected.** The hold threshold ships as a constant (exact value is a planning/tuning decision); configurability is deferred until requested. The countdown loader must honor `UIAccessibility.isReduceMotionEnabled` with a non-animated fallback.

## Requirements

**Gesture model**

- R1. Tapping a QUICK favourite chip opens the staging plate pre-populated with that favourite (name, carbs, portion) instead of logging immediately.
- R2. Press-and-hold on a QUICK favourite chip insta-logs it after a visible countdown loader fills; releasing before the threshold cancels with no log.
- R3. The same tap/hold semantics apply to entries in the recents list (tap already routes to staging via DMNC-761; hold-to-insta-log is new).
- R4. Hypo-treatment favourites (`isHypoTreatment`) keep 1-tap direct log and are exempt from R1/R2.
- R5. Insta-log (hold path) shows a confirmation toast; the staging path needs no toast (saving the plate is the confirmation).

**Hold-to-commit component**

- R6. The countdown loader is a reusable component, not inline view code — DMNC-805 named it `HoldToCommitProgress`.
- R7. The loader respects Reduce Motion: when enabled, replace the fill animation with a non-animated progress indication.
- R8. Hold duration is a single shared constant used by every hold surface.

**Shared toast**

- R9. The toast currently local to `UnifiedFoodEntryView` becomes a shared component: slides from top, auto-dismisses (~2s), supports an UNDO action.
- R10. Existing toast behavior on the meal surface is preserved through the migration.

**Chip + field unification**

- R11. The QUICK favourites chip migrates to a shared `AmberChip` variant supporting two-line content (label + carbs) and the hypo color treatment (cgaGreen).
- R12. `AddBloodGlucoseView` adopts `StepperField` for its glucose value entry, replacing `NumberSelectorView` there.

## Key Flows

- F1. **Re-log via review.** User taps a favourite or recent → staging plate opens pre-populated → user adjusts portion/time if needed → Save commits, Discard cancels. **Covers R1, R3.**
- F2. **Insta-log via hold.** User presses and holds a favourite or recent → loader fills over the hold duration → threshold reached → entry logs, toast confirms with UNDO → user releases early → loader resets, nothing logged. **Covers R2, R3, R5.**
- F3. **Hypo quick add.** Glucose is low, user opens the hypo-filtered entry view → taps a hypo favourite → entry logs immediately, no staging, no hold. **Covers R4.**

## Acceptance Examples

- AE1. Holding a favourite for half the threshold then releasing: no meal entry is created, no toast appears, the loader resets. **Covers R2.**
- AE2. With Reduce Motion on, holding a favourite still insta-logs at the same threshold, but the loader shows non-animated progress. **Covers R7.**
- AE3. A favourite marked `isHypoTreatment` logs on first tap even outside an active treatment cycle. **Covers R4.**
- AE4. Tapping UNDO on the insta-log toast removes the just-created meal entry. **Covers R9.**

## Scope Boundaries

- Expand-from-tag — dropped (see Key Decisions).
- Exercise entry — read-only HealthKit import, no entry path (OOUX catalog).
- Insulin and blood glucose hold gestures — no re-log surface exists for them; their Add views are their staging surface. The issue's "staging plate used by meal + insulin + blood glucose" criterion is satisfied by DMNC-799/800 plus R12.
- Configurable hold duration — deferred until requested (accessibility follow-up belongs to DMNC-797 if it materialises).
- Calibration view — unchanged (OOUX catalog).
- Micro-interaction polish beyond the loader itself — DMNC-797.

## Dependencies / Assumptions

- `AmberChip`, `StepperField`, `QuickTimeChips` exist (`Library/DesignSystem/Components/`, `App/DesignSystem/Components/`) — shipped by DMNC-798/799.
- Staging plate reachable for favourites: DMNC-761 already routes recents through it; the favourite path is assumed to reuse that mechanism (verify during planning).
- The OOUX doc (`docs/brainstorms/2026-04-23-ooux-catalog-and-entry-patterns-requirements.md`) reversal log is the authoritative record of the gesture-model decision.

## Outstanding Questions

**Deferred to planning**

- Exact hold-duration constant (DMNC-805 sketch implied under a second; tune on device).
- Whether the favourite-tap staging route reuses the DMNC-761 recents mechanism or needs its own path.
- `AmberChip` variant shape: content-aware variant vs `@ViewBuilder content:` overload (both named as options in the OOUX doc).

## Sources

- `docs/brainstorms/2026-04-23-ooux-catalog-and-entry-patterns-requirements.md` — object catalog, primitives spec, decision reversal log (§ 2026-04-24).
- `docs/references/staging-plate-pattern.md` — staging plate reference.
- `App/Views/AddViews/UnifiedFoodEntryView.swift` — QUICK chip row, `logFavorite` direct-log call site, local toast.
- Linear: DMNC-805 (decision), DMNC-761 (recents → staging), DMNC-798/799/800 (shipped primitives + decomposition), DMNC-848 (chart-marker parity).
