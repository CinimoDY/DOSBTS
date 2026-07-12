# PLAN: Ratio Lab V2 — reference-ratio line in the Add Insulin sheet

**Linear:** DMNC-1302 (move to In Progress when starting; the dogfooding gate was explicitly lifted by the user on 2026-07-10 — do not re-ask).
**Rank:** 1 of 6 — do this first. Effort: XS (~1 focused hour including verification).

## Goal

When the user has saved a reference ICR in Ratio Lab (`state.confirmedICR != nil`) and the Add Insulin sheet's selected type is **meal bolus or snack bolus**, show one passive, informational line under the UNITS row:

```
REF RATIO 1:12 — SET IN RATIO LAB
```

Display-only. It never computes units, never reads the entered units or carbs, never suggests a dose. It is the Ratio Lab's confirmed reference surfaced at the moment it is educationally relevant.

## Preconditions

1. `cd /Users/doke/extracode/DOSBTS && git pull --ff-only` (main must include Build 129, commit `ee719767` or later).
2. Branch: `git checkout -b claude/dmnc-1302`.

## Exact files to touch

| File | Change |
|---|---|
| `App/Views/AddViews/AddInsulinView.swift` | Add the reference line (only file with code changes) |
| `CHANGELOG.md` | One `Added` entry under `## [Unreleased]` |

Read-only references (do not modify): `App/Views/Settings/RatioLabView.swift` (the REF-row pattern at lines ~176–191), `Library/Content/RatioEstimator.swift` (`icrLabel`).

## Implementation steps (in order)

1. **Read `App/Views/AddViews/AddInsulinView.swift` fully** (182 lines). Note the existing structures you will mirror:
   - The conditional warning insertion point in `body` (lines 46–48):
     ```swift
     if insulinType == .correctionBolus, currentIOB > 0.05 {
         iobWarning
     }
     ```
   - The `iobWarning` view builder (lines 145–161) — an HStack with icon + caption text, amber styling.
2. **Add the visibility condition** in the `VStack` inside `body`, placed **directly after `unitsRow`** (the issue spec says "under the units row" — NOT at the bottom where `iobWarning` sits):
   ```swift
   if let confirmedICR = store.state.confirmedICR,
      insulinType == .mealBolus || insulinType == .snackBolus {
       referenceRatioLine(confirmedICR)
   }
   ```
   `InsulinType` cases are exactly: `.mealBolus, .snackBolus, .correctionBolus, .basal` (`Library/Content/InsulinDelivery.swift:10-14`). Note the sheet's default type is `.snackBolus` (line 15), so the line is typically visible on open when a reference exists.
3. **Add the view builder**, mirroring `iobWarning`'s shape but informational (no icon fill, dimmer palette):
   ```swift
   private func referenceRatioLine(_ icr: Double) -> some View {
       HStack(spacing: 8) {
           Image(systemName: "function")
               .foregroundStyle(AmberTheme.amberDark)
               .frame(height: 14)
           Text("REF RATIO \(RatioEstimator.icrLabel(icr)) — SET IN RATIO LAB")
               .font(DOSTypography.caption)
               .foregroundStyle(AmberTheme.amberDark)
           Spacer()
       }
       .padding(.horizontal, 12)
       .padding(.vertical, 10)
       .background(AmberTheme.surfaceTint)
       .overlay(
           Rectangle()
               .stroke(AmberTheme.borderSubtle, lineWidth: 1)
       )
   }
   ```
   - `RatioEstimator.icrLabel(_:)` is the canonical `1:X` formatter — use it, do not hand-format (`RatioLabView.swift:180` uses the same: `Text("REF RATIO \(RatioEstimator.icrLabel(confirmed))")`).
   - `function` is the same SF Symbol the Settings "Ratios" row uses — keeps the association.
4. **CHANGELOG.md**: under `## [Unreleased]` add:
   ```markdown
   ### Added
   - Add Insulin sheet shows your saved Ratio Lab reference (`REF RATIO 1:X — SET IN RATIO LAB`) as a passive info line for meal/snack boluses — DMNC-1302
   ```
   (If an `### Added` heading doesn't exist under `[Unreleased]` yet, create it. `[Unreleased]` is currently empty.)
5. Build, run, verify (see Acceptance), commit, open PR per repo conventions (`feat(insulin): reference-ratio line in Add Insulin sheet (DMNC-1302)`).

## Cases a weaker model would miss

1. **Do NOT add any state.** `confirmedICR: Double?` already exists as persisted state (`Library/DirectState.swift:140`, reducer case at `Library/DirectReducer.swift:523`, set via `.setConfirmedICR`). No 4-file state dance, no new action, no reducer change. If you find yourself editing `DirectState.swift`/`AppState.swift`, stop — you're off-plan.
2. **Display-only is a safety hard rule.** No math against the entered `units` or any carbs value; no "suggested units"; no tinting the Add button; no tap action on the line. The ratio-lab plan (`docs/plans/2026-07-03-ratio-lab-plan.md` § Safety) forbids any carbs-in→units-out surface. The copy must contain no imperative dosing language ("use", "take", "give" are all banned).
3. **Reactivity comes free — don't add machinery.** `insulinType` is `@State` and `store` is `@EnvironmentObject`, so the `if` in `body` re-evaluates on type switch and on `confirmedICR` changes. Do not add `onChange`/`onReceive` handlers.
4. **Styling tier discipline.** The IOB warning uses full `amber` + `amber.opacity(...)` — that's a *warning*. This line is *informational*: `amberDark` text with the pre-blended semantic tiers `AmberTheme.surfaceTint` (fill) and `AmberTheme.borderSubtle` (stroke). Do NOT write `.opacity()` on palette tokens — `StyleGuardTests` and the design-system enforcement notes treat ad-hoc opacity as a violation (the iobWarning's `amber.opacity(0.08/0.4)` predates the tiers; do not copy that part).
5. **StyleGuard rules apply**: `DOSTypography` only (no `.font(.system(...))`), `.foregroundStyle` (never `.foregroundColor`), `Rectangle().stroke` (no `cornerRadius`), no `Color.black`. Cmd+U runs a source scan that fails on violations.
6. **Sheet plumbing is off-limits.** AddInsulinView is presented through `SheetCoordinator` — do not add a local `.sheet`, do not touch presentation. The change is entirely inside the existing form body.
7. **The default insulin type is `.snackBolus`**, so when a reference exists the line is visible immediately on sheet open — this is intended (meal/snack are the ICR-relevant types). It must disappear when the user taps CORRECTION or BASAL chips, and reappear when they tap back.
8. **`icrLabel` handles rounding** — do not `Int(...)` the Double yourself; a 1:12.4 reference must render exactly as Ratio Lab renders it, or the two surfaces disagree.

## Acceptance criteria

Run each; all must hold:

1. `xcodebuild -project DOSBTS.xcodeproj -scheme DOSBTSApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -configuration Debug build` → succeeds.
2. `xcodebuild -project DOSBTS.xcodeproj -scheme DOSBTSWidget -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -configuration Debug build` → succeeds (no Library/ changes expected, but the widget build is the repo's standing gate).
3. Full test suite green (Cmd+U on simulator, or `xcodebuild test` with the same destination) — including `StyleGuardTests`.
4. Simulator walkthrough (VirtualConnection):
   - With NO reference set (Ratio Lab → CLEAR if needed): open Add Insulin → no ref line for any type.
   - Set a reference in Settings → Insulin → Ratios → SET 1:X AS REFERENCE. Open Add Insulin → line reads `REF RATIO 1:X — SET IN RATIO LAB` under UNITS for MEAL and SNACK; absent for CORRECTION and BASAL; toggling chips shows/hides it live.
   - The line has no tap behavior; entering units does not change it.
5. `grep -n "confirmedICR" App/Views/AddViews/AddInsulinView.swift` shows reads only (no dispatch of `.setConfirmedICR` from this view).
6. CHANGELOG `[Unreleased]` has the entry with ` — DMNC-1302` suffix.

## Bookkeeping

- Linear DMNC-1302 → In Progress at start, Done on merge; note in the issue that the dogfooding gate was lifted 2026-07-10.
- Conventional commit + PR; expect CHANGELOG keep-both merge conflicts if other work lands first.
