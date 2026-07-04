# DMNC-1300: Missed-bolus nudge — WP-N1 log-completeness notification

**Date:** 2026-07-04
**Branch:** claude/dmnc-1300

Part of the MDI Companion track ([DMNC-1291](https://linear.app/lizomorf/issue/DMNC-1291)). This is **WP-N1**, the first MDI notification feature — a single nudge fired ~20 min after a carb-containing meal is logged without a matched bolus. Spec: `docs/plans/2026-07-03-mdi-companion-features-plan.md § WP-N1`.

## What changed

### New files

**`App/Modules/MissedBolusNudge/MissedBolusDetector.swift`** — pure enum with `shouldNudge(meal:deliveries:now:treatmentCycleActive:isHypoTreatmentMeal:showMissedBolusNudge:nudgedMealIds:)`. Thresholds:
- Carbs ≥ 15 g (nil treated as 0)
- Paired bolus: `.mealBolus` or `.snackBolus` within ±15 min of meal timestamp, sum ≥ 0.5 U
- Correction bolus explicitly excluded

**`App/Modules/MissedBolusNudge/MissedBolusMiddleware.swift`** — closure-captured in-memory `Set<UUID>` for dedup. Handles two actions:
- `.addMealEntry` — schedules `UNTimeIntervalNotificationTrigger(timeInterval: 1200, repeats: false)` via `DirectNotifications.shared.addNotification`
- `.addInsulinDelivery` — cancels pending nudges for meals within the pairing window when a meal/snack bolus lands

### State — 4-file lockstep

- **`Library/DirectState.swift`** — `showMissedBolusNudge: Bool { get set }`
- **`Library/Extensions/UserDefaults.swift`** — key `libre-direct.settings.show-missed-bolus-nudge`, default `true`
- **`App/AppState.swift`** — `didSet` + `init` read from UserDefaults
- **`Library/DirectReducer.swift`** — `setShowMissedBolusNudge(enabled:)` case

### `App/App.swift` — `missedBolusNudgeMiddleware()` added to both `createSimulatorAppStore` and `createAppStore`, after `tightControlStreakMiddleware()` with cross-middleware comment

### `App/Views/Settings/AlarmSettingsView.swift` — toggle in `globalSection` between predictive low alarm and celebrations; footer line added

### `DOSBTSTests/MissedBolusDetectorTests.swift` — 13 detector tests + 2 reducer tests (new file, registered in pbxproj)

## Decisions worth flagging

- **Hypo suppression without `MealEntry.isHypoTreatment`.** `FavoriteFood.isHypoTreatment` exists but `toMealEntry()` doesn't carry it forward. Middleware derives `Set<String>` of hypo-treatment descriptions from `state.favoriteFoodValues` and passes `isHypoTreatmentMeal: Bool` to the pure detector. Description-based matching is correct — the favorite food IS the hypo treatment, and any logged meal with that exact description is one too.

- **Race condition: `treatmentLoggedAt` not `treatmentCycleActive`.** When `.logHypoTreatment` dispatches, `TreatmentCycleMiddleware` emits both `.addMealEntry` and `.startTreatmentCycle` sequentially. When my middleware sees `.addMealEntry`, `treatmentCycleActive` is still `false` (`.startTreatmentCycle` hasn't processed). `state.treatmentLoggedAt` IS already set (from the `.logHypoTreatment` reducer), so guarding `state.treatmentLoggedAt == nil` catches the race window correctly.

- **In-memory dedup, not persisted.** The `Set<UUID>` resets on app kill — acceptable per spec. The notification identifier encodes `meal.id.uuidString`, so re-scheduling after a restart is idempotent (UNUserNotificationCenter silently replaces a pending request with the same identifier).

- **Log-completeness framing, not dose advice.** Notification copy: "Meal logged — no bolus recorded. Forgot to log it, or still to dose?" — question mark, no instruction. This keeps it squarely in the "did you forget to LOG it?" lane, not "you SHOULD dose now."

- **No `.addMealEntry` from `.logHypoTreatment`.** Confirmed by reading `TreatmentCycleMiddleware`: the hypo flow dispatches `.addMealEntry` via its own middleware, but the race-condition guard (`treatmentLoggedAt`) already blocks the nudge for that path. Belt-and-suspenders: even if the guard weren't there, `isHypoTreatmentMeal` suppression would catch it.

## Tests

`** TEST SUCCEEDED **` — all 15 new tests pass (13 detector matrix + 2 reducer toggle/persistence), and the **full `DOSBTSTests` suite is green** (no regressions) on iPhone 17 Pro / iOS 26.5.
