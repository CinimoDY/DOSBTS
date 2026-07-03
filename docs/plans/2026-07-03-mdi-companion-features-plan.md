# MDI Companion Features — Plan (2026-07-03)

Two small features selected in the 2026-07-03 ideation session, both grounded in data/infrastructure the app already has. Independent of each other and of the polish cycle; each is one conductr-sized PR.

---

## WP-N1 — Missed-bolus nudge (S–M)

**Problem:** on MDI, forgetting to bolus (or forgetting to *log* the bolus) after a logged meal is common and costly. The app already knows both halves: `MealEntry.carbsGrams` and `InsulinDelivery` timing.

**Behavior:** when a meal with **carbs ≥ 15 g** is logged and **no meal/snack bolus exists within ±15 min** of the meal timestamp after a **~20 min grace period**, fire exactly **one** local notification:

> "Meal logged — no bolus recorded. Forgot to log it, or still to dose?"

Wording is deliberately **log-completeness framing** — it asks about the record, never advises a dose.

**Mechanics:**
- New small middleware (`App/Modules/MissedBolusNudge/`) watching `.addMealEntry` — this is cross-middleware listening on an action `mealEntryStoreMiddleware` also handles: **comment the cross-dependency** (CLAUDE.md rule).
- Grace check: schedule the check ~20 min after meal timestamp (timer or evaluate on the next glucose tick, whichever is simpler/testable — extract the decision into a **pure function** `MissedBolusDetector.shouldNudge(meal:deliveries:now:settings:) -> Bool`).
- Pairing definition identical to Ratio Lab's: meal/snack bolus within ±15 min, summed ≥ 0.5 U counts as "bolused".
- **Suppress when:** `treatmentCycleActive` (hypo carbs are deliberately uncovered); the meal is a hypo-treatment favorite (`FavoriteFood.isHypoTreatment` / the filtered-entry route); the toggle is off.
- **Dedup:** at most one nudge per meal entry (persist last-nudged meal id or in-memory set + idempotent scheduling).
- Toggle: `showMissedBolusNudge` (default **on**) in Settings → Alarms & Alerts — 4-file lockstep (DirectState / AppState / UserDefaults / DirectReducer + DirectAction case).
- Notification: `UNUserNotificationCenter` local notification via the existing notification-middleware idioms (`GlucoseNotification` module is the reference); no new notification category/actions needed in V1.
- Register middleware in **BOTH** `App/App.swift` arrays.

**Tests:** pure `MissedBolusDetector` matrix (carbs 10 g → no; bolus at +12 min → no; bolus at +20 min → yes-nudge; treatment cycle active → no; hypo favorite → no; second evaluation of same meal → no) appended to an existing suite or a new registered test file; reducer test for the toggle.

**Acceptance:** simulator — log a 30 g meal without bolus → exactly one nudge after grace; log meal + bolus → none; hypo-treatment meal during a cycle → none. CHANGELOG Added entry.

---

## WP-N2 — "What spikes me" food ranking (S)

**Problem:** the app already computes per-food glycemic response (`PersonalFood.avgDeltaMgDL`, updated from clean-meal `MealImpact` observations with `observationCount`) — but never shows it anywhere. Zero collection work; pure surfacing.

**Behavior:** a pushed screen from the **Lists tab** ("FOOD IMPACT" row or section link — implementer places it consistently with existing Lists navigation): all scored `PersonalFood`s ranked by `avgDeltaMgDL` descending:

```
PASTA CARBONARA      +64 avg · n=5
PORRIDGE & BERRIES   +38 avg · n=7
GRILLED CHICKEN SALAD +12 avg · n=4
```

- Color-code the delta by the existing MealImpact delta-tier thresholds (cgaGreen / amber / cgaRed) — reuse the same constants, do not invent new bands.
- Show `n=` observation count (confidence); consider dimming n<3 rows (amberDark) rather than hiding them.
- `DOSEmptyState` when no scored foods yet: title `NO SCORED FOODS YET`, detail explaining scores accumulate from clean meals (no correction/exercise/stacked meal in the 2 h window).
- Footer caption: scores are personal averages from clean-meal observations — reference only.
- Data: load via the existing PersonalFood store patterns (GRDB middleware load into state, or reuse whatever `personalFoodValues`-style loading exists — follow the data-load guard pattern: `.active` guard).
- UI: List/rows with DOSTypography + tokens; must pass StyleGuardTests.

**Tests:** ranking/sort + tier-mapping display-model tests appended to an existing suite.

**Acceptance:** simulator with seeded PersonalFood rows shows ranked, color-coded list; empty install shows the empty state. CHANGELOG Added entry.
