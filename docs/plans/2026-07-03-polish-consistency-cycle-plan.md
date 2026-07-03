# Polish & Consistency Cycle — Plan (2026-07-03)

Post-DMNC-1211 cycle. Goal: the app *behaves* as consistently as it now *looks* — "always in the same spot", uniform feedback, no content sliding under the bottom bar. Five work packages (WP-P1…P5), each one conductr-sized PR. Findings come from a 2026-07-03 behavioral audit; line numbers reference main @ `4817500d` — re-locate by symbol if drifted.

## Dependency graph

```
P1 (bar fix)          — independent
P2 (same-spot)        — independent
P3 (feedback parity)  — independent
P4 (interaction)      — blocked by P3 (shares the generalized toast)
P5 (cosmetics)        — independent
```

All packages: app + widget targets build, full suite green (incl. StyleGuardTests), CHANGELOG `[Unreleased]` entry when user-visible.

---

## WP-P1 — Bottom bar overlap fix (S)

**Bug:** scrolled content shows through/beneath the persistent INSULIN/MEAL bar; behavior differs per tab (user-reported: "content is just a bit beneath the buttons… looks unprofessional").

**Root causes** (`App/Views/SharedViews/GlucoseStatusBar.swift`):
1. `GlucoseStatusBar`'s outer `VStack` has **no background** — only the inner HStack (`AmberTheme.dosBlack`) and the Divider are opaque, so List content shows through the container's transparent regions.
2. `safeAreaInset(edge: .bottom)` is applied in `GlucoseFramedTab` to the tab `content()` (the `NavigationStack`). `ScrollView` (Digest) receives the inset correctly; `List` scroll layers (Lists tab, Settings tab) and **all pushed detail screens** (Settings category screens, CalibrationsView, Lists details) do not reliably inherit it — their last rows scroll under the bar.

**Fix shape:**
- Add `.background(AmberTheme.dosBlack)` to the bar's outer container.
- Restructure so the inset is applied where `List`s actually receive it — inside the `NavigationStack` wrapping the root content (pushed screens inherit a `NavigationStack`-inner inset). Keep ONE mounting pattern for all four tabs; do not add per-screen bars (that recreates divergence).
- Overview already works via direct `safeAreaInset` (keep; see `docs/solutions/ui-bugs/swiftui-vstack-overflow-sinks-safeareainset.md` for its GeometryReader subtlety).

**Acceptance:**
- Scroll to the last row on all 4 tabs AND ≥2 pushed screens (a Settings category, CalibrationsView): last row fully clears the bar.
- Bar renders at pixel-identical position/height on every tab (screenshot comparison).
- No double-inset (blank gap) on Digest/Overview after the change.
- CHANGELOG: Fixed — "content no longer scrolls beneath the INSULIN/MEAL bar".

---

## WP-P2 — "Same spot" persistence (S–M)

Two `@State` properties silently reset while sibling settings persist — the core "not in the same spot" complaint:

1. **Chart report type** (`selectedReportType`: GLUCOSE / TIME IN RANGE / STATISTICS) — `@State` in `OverviewView`; resets on tab switch/relaunch while chart zoom (3h/6h/12h/24h) and statistics days persist in Redux. Move to Redux + UserDefaults via the 4-file lockstep (`Library/DirectState.swift`, `App/AppState.swift` didSet+init, `Library/Extensions/UserDefaults.swift` Keys+accessor, `Library/DirectReducer.swift`; new action in `Library/DirectAction.swift`). `ChartToolbar` binds to the store value.
2. **Collapsed sections** (`CollapsableSection` in the Lists tab) — `@State`, re-collapse on every visit. Persist per-section expansion keyed by a stable section identifier (UserDefaults-backed; dictionary setting or per-list booleans — implementer's choice, follow the simplest 4-file-compatible shape).

**Acceptance:** set report type to STATISTICS, expand two list sections, kill + relaunch → both restored. Reducer tests for the new actions (append to `DOSBTSTests/DirectReducerTests.swift`, use `makeTestDefaults()`).

---

## WP-P3 — Feedback parity (S–M)

Quick-logged meals get `LoggedMealToast` (+UNDO) and AI/barcode flows get success haptics; everything else logs silently:

| Action | Toast today | Haptic today |
|---|---|---|
| Meal via favorite/recent tap | ✓ (+UNDO) | ✗ |
| Meal via manual form | ✗ | ✗ |
| Insulin logged | ✗ | ✗ |
| Blood glucose logged | ✗ | ✗ |

**Fix:**
- Generalize the logged-toast (one entry-type-aware component or siblings — reuse `.dosCard(.toast)` chrome) and fire it for ALL log actions: manual meal path, insulin + BG callbacks in `App/Views/RootSheetContent.swift`. Keep UNDO where the delete is trivially reversible (meals today; insulin/BG UNDO = delete the created row — include if simple).
- `.hapticNotification(.success)` (existing action) on every successful log.

**Acceptance:** each of the four log paths shows a toast + haptic; UNDO removes the entry. No toast/haptic change for non-log actions.

---

## WP-P4 — Interaction parity (M) — *blocked by P3*

1. **Swipe-action parity:** `MealItemRow` has leading Log-Again + trailing Delete/Add-to-Favorite + context menu; insulin/BG/sensor lists have bare `.onDelete`. Bring trailing-swipe Delete to `BloodGlucoseListView`, `InsulinDeliveryListView`, `SensorGlucoseListView` (MealItemRow is the idiom source; no Log-Again for measurements). Tap-to-edit only where an editor exists (insulin → existing `CombinedEntryEditView` path; BG/sensor: none — delete-only).
2. **Swipe-dismiss protection:** `interactiveDismissDisabled()` on `AddInsulinView`, `AddBloodGlucoseView`, `AddCalibrationView` (only `AddMealView` has it today — same half-typed-data rationale).
3. **Delete-confirmation policy** (align + document in `docs/design-system.md`): swipe-delete stays immediate BUT pairs with the P3 undo-capable toast; modal Delete buttons keep their `confirmationDialog`.

**Acceptance:** swipe-delete works uniformly across the four list types; entry sheets can't be swipe-dismissed with unsaved input; policy paragraph added to design-system.md.

---

## WP-P5 — Cosmetic sweep (S, one PR)

1. `InsulinDeliveryListView`: "IE" → "U" (German-upstream leftover; prefer one shared insulin-units formatting helper so it can't diverge again).
2. `role: .cancel` on all form Cancel buttons (AddMealView, AddInsulinView, CombinedEntryEditView, …).
3. `.navigationBarBackButtonHidden(true)` on `AddBloodGlucoseView` + `AddCalibrationView` (redundant back+Cancel affordances today).
4. Button-label convention, rename mismatches: **Add** = create new entry, **Save** = persist edit, **Done** = close without mutation.
5. design-system.md note: full-screen entry sheets vs `[.medium, .large]` detented read/edit overlays is **intentional** (focus vs context) — document, don't change.

**Acceptance:** greps for "IE" gone; all Cancels carry the role; convention documented.
