# RATIO LAB — ICR/ISF Workbench Plan (2026-07-03)

An insulin-to-carb-ratio (ICR) and correction-factor (ISF) workbench: teaches the method, computes estimates from the user's own logged data, and never gives dosing commands. Discoverable in Settings → Insulin (nothing up front). Three work packages: **WP-R1 estimator → WP-R2 wiring → WP-R3 UI** (strictly sequential).

## Safety rules (apply to every string and surface in this feature)

- Voice: "your data suggests", "estimate", "reference" — never imperative dosing language; never render "take/inject N units".
- **No carbs-in→units-out input field anywhere** — that would be a bolus calculator, deliberately out of scope forever.
- Every number ships with its uncertainty (N, day count, spread).
- Two fixed disclaimers: `REFERENCE ESTIMATES — NOT DOSE ADVICE` (under the estimates grid) and `ESTIMATES ARE EDUCATIONAL REFERENCE ONLY. DISCUSS RATIO CHANGES WITH YOUR CARE TEAM.` (screen footer).
- The confirmed reference ratio is display-only in V1. Surfacing it in AddInsulinView (V2) is a **separate, explicitly user-gated decision** after dogfooding — do not implement in this cycle.

## Clinical formulas (cite in doc comments + explainer copy)

- **500 rule** (Walsh, *Using Insulin*): ICR = 500 / TDD (500 for rapid analogs — matches both `InsulinPreset` cases; 450 variant is for regular insulin, not needed).
- **1800 rule**: ISF = 1800 / TDD in mg/dL; mmol/L display converts the mg/dL result via the existing `exchangeRate` (equivalent to the "100 rule").
- **Empirical ICR**: median of carbs÷bolus over qualifying clean meals; spread = P25–P75.

---

## WP-R1 — `RatioEstimator` (pure logic + tests) (S–M)

**New file `Library/Content/RatioEstimator.swift`** (~220 LOC; pattern: `IOBCalculator.swift`, `TightControlStreakDetector`):

```swift
struct TDDDay: Equatable          { let date: Date; let basalUnits: Double; let bolusUnits: Double } // bolus = meal+snack+correction
struct MealObservation: Equatable { let meal: MealEntry; let impact: MealImpact; let pairedBolusUnits: Double
                                    let endGlucose: Int?; let minGlucoseInWindow: Int? }
struct RatioEvidence: Equatable   { let tddDays: [TDDDay]; let mealObservations: [MealObservation] }

enum MealExclusionReason: Equatable { case noBolus, noBaseline, baselineOutOfRange, smallMeal, tinyBolus,
                                      didNotReturnToBaseline(deltaMgDL: Int), hypoInWindow, implausibleRatio }
struct ScoredMealObservation { let observation: MealObservation; let ratio: Double?; let exclusion: MealExclusionReason? }

struct RatioEstimates {
    let averageTDD: Double?                 // median of qualifying days
    let qualifyingDayCount: Int
    let fiveHundredRuleICR: Double?         // nil until ≥5 qualifying days
    let eighteenHundredRuleISFMgDL: Double? // same gate; view converts for mmol
    let empiricalICR: Double?               // median; nil until ≥5 qualifying meals
    let empiricalICRSpread: ClosedRange<Double>?
    let scoredObservations: [ScoredMealObservation] // ALL candidates, for the evidence table
}
enum RatioEstimator { static func estimate(evidence: RatioEvidence) -> RatioEstimates }
```

**TDD day qualifies iff** (rules assume a complete, representative day):
- complete: `date < startOfToday`, within last 14 complete days;
- ≥1 basal AND ≥1 bolus logged that day (basal-only / bolus-only = logging gap for an MDI user, not a low-insulin day); basal attributed to its `starts` date (consistent with `DailyDigest`);
- **gate: ≥5 qualifying days**; aggregate = **median** TDD (robust to a forgotten bolus — comment why not mean).

**Meal observation qualifies iff** (each failure maps to one `MealExclusionReason` — the UI shows these as teaching tags):
1. `impact.isClean == true` (existing `MealImpactStore` confounder detection: correction-in-window / exercise overlap / stacked meal);
2. baseline exists and **70 ≤ baseline ≤ 180 mg/dL** (low start → rescue carbs distort; high start → bolus is part-correction);
3. paired meal/snack bolus **≥ 0.5 U** within **±15 min of meal.timestamp, summed** (time-window, NOT timegroup equality — floor-rounding splits 12:14/12:16);
4. carbs **≥ 15 g** (below that, ±5 g estimation error dominates);
5. no hypo in window: min glucose in [t, t+2h] **≥ 70** (a low proves overshoot + likely unlogged rescue carbs);
6. returned near baseline: `|endGlucose − baseline| ≤ 30 mg/dL`, endGlucose = reading nearest t+120 within t+105..t+135 (CGM-gap tolerant); missing → excluded;
7. sanity clamp: ratio within **2–50 g/U** else `implausibleRatio`.
- **Gate: ≥5 qualifying meals.** All thresholds `static let` (test-pinned). Known limitation (comment): the 2h window under-detects slow high-fat meals; criterion 6 excludes them — conservative in the right direction.

**New test file `DOSBTSTests/RatioEstimatorTests.swift`** — ⚠️ tests are NOT auto-synced: 4 manual pbxproj entries mirroring `DesignTokenPinTests` (PBXBuildFile / PBXFileReference / DOSBTSTests group / PBXSourcesBuildPhase). Coverage:
- 500 rule (TDD 50 → 1:10), 1800 rule (TDD 50 → 36), nil below 5-day gate;
- TDD qualification matrix: partial today excluded; basal-only excluded; bolus-only excluded; median-not-mean pinned with skewed fixture;
- one test per exclusion reason (noBolus, noBaseline, baseline 65, baseline 190, 10 g meal, 0.25 U bolus, ended +54, hypo 62 in window, 80 g/U implausible);
- pairing: boluses at −10 and +12 min summed; +20 min ignored;
- aggregation: median + P25–P75 pinned exactly; n=4 → nil, n=5 → value;
- endGlucose selection: +110 vs +130 → nearest-to-+120 wins; none in +105..+135 → excluded.

## WP-R2 — Wiring (S) — *blocked by R1*

On-demand load (cold path — the screen is opened rarely; do NOT compute on app-activation like MealImpactStore):

```
RatioLabView.onAppear → dispatch .loadRatioEvidence
  ratioLabMiddleware (guard state.appState == .active; shape: IOBMiddleware)
    └─ DataStore.getRatioEvidence()  — ONE asyncRead, NO writes inside (GRDB deadlock rule):
        1. InsulinDelivery, starts in [startOfDay(today−14d), startOfToday) — filter type in Swift (InsulinType is Codable, not SQL-filterable)
        2. MealImpact where isClean, timestamp ≥ now−30d (MealImpactStore backfill bound), joined in Swift to MealEntry by mealEntryId
        3. per candidate: SensorGlucose in [t, t+135min] → endGlucose + minGlucoseInWindow
        4. per candidate: meal/snack boluses within ±15 min, summed
  → emit .setRatioEvidence(evidence:)
RatioLabView renders RatioEstimator.estimate(...) in a computed property (pure)
```

- **New file** `App/Modules/RatioLab/RatioLabMiddleware.swift` (~150 LOC, includes the `DataStore` extension). Register in **BOTH** `App/App.swift` middleware arrays.
- State: `ratioEvidence: RatioEvidence?` **transient** (3-file pattern, like `scoredMealEntryIds` / `selectedSettingsCategory` — no UserDefaults); `confirmedICR: Double?` **persisted** (4-file lockstep; optional-Double accessor pattern like `dailyDigestReminderHour`: `object(forKey:) != nil` guard + `removeObject` on nil).
- Actions (`Library/DirectAction.swift`, new `// MARK: Ratio Lab` block): `loadRatioEvidence`, `setRatioEvidence(evidence:)`, `setConfirmedICR(icr: Double?)` (nil clears).
- Reducer tests appended to `DirectReducerTests.swift` (`makeTestDefaults()`; verify confirmedICR UserDefaults round-trip via `AppState(defaults:)`).

## WP-R3 — UI (M) — *blocked by R2*

**Entry point** — `App/Views/Settings/InsulinSettingsView.swift`: new `Section`, header `Label("Ratios", systemImage: "function")`, `NavigationLink` row "Ratio Lab" (+ once set, a static `REF 1:12` line). Footer: "Estimate your insulin-to-carb ratio and correction factor from your own logged data. Reference only." Push happens inside SettingsView's existing `NavigationStack` — no sheets.

**New file `App/Views/Settings/RatioLabView.swift`** (~320 LOC incl. private `RatioEvidenceRow` + `CleanExperimentCard`): `ScrollView` > `VStack(spacing: DOSSpacing.md)`, `.dosNavigationTitle("Ratio Lab")`. Must pass StyleGuardTests: tokens only, sharp corners, DOSTypography roles, no bare `ProgressView()`. Top-to-bottom:

1. **Explainer card** — `.dosCard(.info)` with `.dosHeader(AmberTheme.cgaCyan)` "WHAT IS AN ICR?": 3–4 lines (1:X = 1 U covers X g; ISF = drop per unit; the lab estimates both from logged data). Optional `stagedReveal` cascade (Reduce-Motion-safe stepping per DOSModifiers docs).
2. **ESTIMATES grid** — 3 × `StatCard` (LazyVGrid, DigestView.statsGrid pattern):
   - `500 RULE` → `1:12`, help `TDD 41.5U · 12 DAYS`
   - `YOUR MEALS` → `1:11`, help `n=7 · 9–14 SPREAD`
   - `1800 RULE ISF` → `43`, help `MG/DL PER UNIT` (mmol: converted value + `MMOL/L PER UNIT`, per `state.glucoseUnit`)
   - gated: value `—`, help `NEED 5 DAYS` / `NEED 5 MEALS`
   - fixed caption below: `REFERENCE ESTIMATES — NOT DOSE ADVICE`
3. **REFERENCE row** — `REF RATIO 1:12 · SET 14 JUN` + `SET 1:X AS REFERENCE` (uses empirical when available, else 500-rule) + `CLEAR`; dispatches `.setConfirmedICR`. Ghost `DOSButtonStyle`.
4. **EVIDENCE table** — bespoke compact `RatioEvidenceRow` (do NOT reuse MealItemRow — wrong display model + swipe affordances): `14 JUN 12:40 · PASTA … 60g / 5.0U → 1:12`. Qualifying rows amber; excluded rows amberDark with reason tag replacing the ratio: `NO BOLUS`, `ENDED +54`, `HYPO`, `LOW START`, `SMALL MEAL` — **exclusion reasons are the teaching mechanism**; newest first.
5. **CLEAN EXPERIMENT card** — the guidance checklist, always present (`[ ]` glyph lines): start in range 80–180 with no active IOB; eat a known-carb meal (packaged/weighed helps); bolus your usual ratio, log carbs + units within 15 min; hands off 2 h — no corrections, snacks, or exercise; at 2 h: within ±30 of start and no low → ratio held; ended high → too weak; went low → too strong; repeat to 5 qualifying meals.
6. **Safety footer** — `DOSTypography.caption`, amberDark: `ESTIMATES ARE EDUCATIONAL REFERENCE ONLY. DISCUSS RATIO CHANGES WITH YOUR CARE TEAM.`

**Empty/low-data state:** zero estimates → explainer, `COLLECTING EVIDENCE 0/5` progress line, checklist front-and-center (this IS the "nice guidance" moment), safety footer. `n/5` counter also on the gated YOUR MEALS card. Loading: `FiguresLoadingView.inline`.

**Ships with:** CHANGELOG `[Unreleased]` Added entry; CLAUDE.md architecture bullet ("Ratio Lab").

## Deferred (backlog issues, NOT this cycle)

- **V2 — AddInsulinView reference line**: passive `REF RATIO 1:12 — SET IN RATIO LAB` under the units row for meal/snack bolus types, styled like the IOB stacking warning but informational. Display-only, no math against entered units. **Gated on an explicit user decision after dogfooding V1** (moves reference info into a dosing context).
- **V3 — Empirical ISF**: wire the existing, unwired `Library/Content/InsulinImpact.swift` (correction-dose impact model + confounders, tests exist, zero call sites) for observed drop-per-unit from clean correction boluses. Deferred: clean correction events are sparse for one user; the 1800-rule card covers ISF in V1.

## Manual verification (WP-R3 acceptance)

Simulator with VirtualConnection/Debug seed data: empty state (fresh install) → gated (n<5) → full state; confirm + clear reference; mmol toggle in Glucose settings converts the ISF card; all StyleGuardTests pass.
