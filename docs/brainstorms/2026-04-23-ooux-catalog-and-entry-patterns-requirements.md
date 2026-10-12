> **Superseded by docs/ooux/ (2026-10-12)** — see [`docs/ooux/entity-map.html`](../ooux/entity-map.html) and [`docs/ooux/README.md`](../ooux/README.md). Kept for history and the entry-pattern specs.

# OOUX Catalog + Entry Patterns

**Issue:** [DMNC-795](https://linear.app/lizomorf/issue/DMNC-795) (High)
**Scope:** Design-only. Defines object catalog + shared primitives for single-object entry + per-feature mapping. Component implementation and view migrations are tracked in follow-up Linear issues (DMNC-798, DMNC-799, DMNC-800).
**Related (not hard-blocked):** DMNC-791 (Figma library) consumes § Pattern 2's primitives list + chip visual treatment, not the full object catalog. DMNC-796 (unified entry interactions) is where tap/long-press semantics are properly owned — this spec does not pre-decide those. DMNC-797 (micro-interactions polish) layers accessibility + motion on top of the primitives.

**Revision history:** Drafted 2026-04-23. Revised same day after two passes of six-persona document review dropped `CategoryPanel`, demoted `StagingPlate` to provisional, removed favourite long-press, reframed Context away from asserted user pain, and resolved a number of implementation-shape details flagged as feasibility risks.

---

## Context

DOSBTS entry surfaces have grown feature-by-feature. Two concrete pressures drive this spec — neither is a user-reported pain:

**1. Maintenance surface.** `FoodPhotoAnalysisView` is 882 lines and conflates AI analysis, staging-review, follow-up conversational clarification, inline barcode-child navigation, cross-row focus coordination, portion scaling, and final commit into one view. It is the largest view in the app and the one most likely to be disturbed during unrelated refactors.

**2. Forward-looking code reuse.** Three upcoming surfaces (DMNC-796 unified entry interactions; DMNC-797 micro-interactions polish; DMNC-791 Figma library prep) will re-solve the same sub-problems — numeric input with custom step + tap-to-type, relative-time picker, amber chip — unless shared primitives exist.

### Identity bet (stated explicitly)

The primitives this spec introduces (`StepperField`, `QuickTimeChips`, `AmberChip`) adopt **consumer-iOS interaction conventions** — stepper + tap-to-type numeric entry, relative-time chip presets, segmented chip-row category selectors. These are idioms readers encounter daily in Apple Health, Fitness, Reminders, Oura, and similar apps.

DOSBTS's DOS amber CGA identity is upheld at the **visual and typographic layer** (monospace fonts, amber phosphor palette, sharp corners per `AmberTheme.swift` + `DOSTypography.swift`), not at the **interaction-grammar layer**. Chips are amber. Numeric buttons are amber. Time presets are amber. But the *shape* of the interactions matches common iOS grammar — intentionally, to lower the cognitive cost for diabetic users who cross-reference many iOS health apps. If DOSBTS later wants a terminal-first entry grammar (slash commands, abbreviation parsers), that's a deliberate pivot away from this spec's bet, and this paragraph exists so the pivot can be argued against the stated position rather than discovered by archaeology.

## Object catalog

This catalog is **durable reference documentation**, not a one-shot input to a specific follow-up issue. Future specs (particularly DMNC-791 for Figma vocabulary and DMNC-796 for interaction decisions) will reference it. Expect it to migrate to `docs/architecture.md` or a dedicated `docs/object-catalog.md` once more than one brainstorm document references it.

### Entry objects

#### Meal (`MealEntry`)
**A logged food intake event with carbs, description, and time.**

| Attribute | Type | Source |
|---|---|---|
| id | UUID | generated |
| timestamp | Date | user / now |
| mealDescription | String (≤200) | user / AI / barcode / favourite |
| carbsGrams | Double? (0–1000) | user / AI / OFF / favourite |
| analysisSessionId | UUID? | AI analysis (links to `PersonalFood` learning) |

- **State transitions:** staged → logged → edited | deleted
- **CTAs:** add (photo / barcode / text / manual / favourite), edit, delete, save-as-favourite
- **Relationships:**
  - → **GlucoseReading** — 2-hour post-meal impact window (`MealImpactStore` middleware)
  - → **InsulinDelivery** — bolus coverage / confounder detection
  - → **PersonalFood** — UUID-convention link via `analysisSessionId` (not a typed reference; runtime join at `ChartView.swift:735-736`)
  - ← **Favourite** — factory-method link via `FavoriteFood.from(mealEntry:)` + `.toMealEntry()` (not a stored back-reference)
- **Approach:** In-place decomposition of the 882-LOC `FoodPhotoAnalysisView` first (tracked in DMNC-800). A reusable batch-review component (Pattern 1) is **provisional and extracted only if** the in-place refactor reveals a clean shared shape. **Favourite tap = 1-tap direct log (unchanged).** Edit-before-log is out of scope; post-log edit remains available via chart-marker tap (already implemented).

#### InsulinDelivery (`InsulinDelivery`)
**A logged insulin dose of a given type, at a given time, with duration (basal only).**

| Attribute | Type | Source |
|---|---|---|
| id | UUID | generated |
| starts | Date | user / now |
| ends | Date | = starts (bolus) / user (basal) |
| units | Double (>0) | user |
| type | `InsulinType` (`mealBolus` / `snackBolus` / `correctionBolus` / `basal`) | user |

- **State transitions:** logged → edited | deleted
- **CTAs:** add, edit (chart marker tap), delete
- **Relationships:**
  - → **GlucoseReading** — IOB projection (oref0 Maksimovic exponential decay, DIA-window filtered; see `IOBCalculator`, `IOBMiddleware`)
  - ← **Meal** — meal / snack bolus coverage (confounder for meal-impact analysis)
- **Approach:** Inline redesign of `AddInsulinView` using the shared primitives (`StepperField`, `QuickTimeChips`, `AmberChip`) directly, with a custom amber-chip row for type selection + `switch` on the enum in body. **No category-wrapping component.** See § Pattern 2 for the primitives.

#### BloodGlucose (`BloodGlucose`)
**A manually logged / fingerstick blood glucose value at a given time. Used for sanity checks and calibration.**

| Attribute | Type | Source |
|---|---|---|
| id | UUID | generated |
| timestamp | Date | user / now |
| glucoseValue | Int (mg/dL, ~40–500) | user |

- **State transitions:** logged → deleted (rarely edited)
- **CTAs:** add, delete
- **Relationships:** → **GlucoseReading** (calibration input; may influence `CustomCalibration` regression)
- **Approach:** **Direct entry — no change.** `AddBloodGlucoseView` (54 LOC) + `NumberSelectorView` is already the right shape. May later adopt `StepperField` for Int-vs-Double parity once that primitive ships, but that's out of scope here.

### Read / monitoring objects

*Named here to document relationships into entry objects; none have entry paths.*

- **GlucoseReading (`SensorGlucose`)** — primary read object. Continuous sensor-derived values with smoothed trend and minute-change slope. **Central data spine** — every entry object relates to it (impact, IOB, calibration), every derived object reads from it.
- **Sensor (`Sensor`)** — physical BLE/NFC transmitter. Lifecycle: `paired → active → expired`.
- **TreatmentCycle** — guided Rule-of-15 hypo workflow (`TreatmentCycleMiddleware`). Lifecycle: `prompted → active (countdown) → rechecking → stabilised | treat-again`. References **GlucoseReading** (recheck target) and **Meal** (hypo treatment entries via the hypo-filtered variant of `UnifiedFoodEntryView`).
- **Alarm** — threshold event (low / high / predictive-low). Lifecycle: `fired → snoozed | acknowledged`. Derived from GlucoseReading evaluation; may trigger TreatmentCycle.
- **DailyDigest (`DailyDigest`)** — per-day aggregated stats + AI insight (Claude Haiku). Lifecycle: `computed-on-demand → cached`. Aggregates all three entry objects + GlucoseReading + Exercise.
- **Exercise** — HealthKit-imported workout. Read-only in DOSBTS — no entry path. Referenced by `MealImpact` confounder detection and DailyDigest timeline.
- **Favourite (`FavoriteFood`)** — meta-object. Curated Meal template with pre-set name and carbs. Factory-method link to Meal (not a stored back-reference).
- **Goal/limit** — setting, not a logged object. `alarmLow` / `alarmHigh` / glucose target range. Referenced by Alarm (thresholds), chart band colouring, DailyDigest (TIR%).

## Object map

The ASCII fallback below is **canonical and current.** The SVG at `.devjournal/sessions/dmnc-795-ooux-brainstorm-2026-04-23/L2-thematic/object-map.svg` is retained for session context but shows the pre-review draft's `[P1] StagingPlate` / `[P2] CategoryPanel` labels; refer to the ASCII or to § Pattern 1 / § Pattern 2 for the committed approach.

```
                        ┌───────────┐
                        │  SENSOR   │
                        └─────┬─────┘
                              │ source
                              ▼
┌──────────┐         ┌──────────────────────┐         ┌──────────┐
│ FAVOURITE│─ tpl ─▶│   GLUCOSE READING     │◀─ HK ──│ EXERCISE │
└──────────┘         │ (central data spine) │         └──────────┘
                     └──▲────▲────▲─────────┘
                   impact│   │    │calibration
                         │  IOB   │
┌────────────┐           │   │    │           ┌─────────────────┐
│   MEAL     │───────────┘   │    └───────────│   INSULIN       │
│ (Pattern 1 │◀── bolus pairing / confounder ─│   DELIVERY      │
│ provisional)│                │                │ (primitives)    │
└────────────┘                 │                └─────────────────┘
      │                        │                      │
      │                        ▼                      │
      │                   ┌────────┐                  │
      │          ┌────────│ ALARM  │◀─ thresholds ────┤
      │          │        └───┬────┘  (Goal/limit)    │
      │          │            │ trigger               │
      │          │            ▼                       │
      │          │     ┌──────────────┐               │
      │          └─────│  TREATMENT   │─ recheck ─────┤
      │                │    CYCLE     │               │
      │                └──────────────┘               │
      │                                               │
  ┌───▼────────────────────────────────────────────▼───┐
  │ BLOOD GLUCOSE         DAILY DIGEST                  │
  │ (direct entry)   ◀── aggregates GR + all entry ──▶  │
  └─────────────────────────────────────────────────────┘
```

## Pattern 1 — Batch-review surface (provisional; extraction deferred)

The batch-review concept is real — food photo, barcode, and text paths all produce a small list of candidate items the user should see and edit before a single commit. But the **reusable component API cannot be responsibly designed before the first real extraction attempt.** The current staging-plate code lives in `FoodPhotoAnalysisView.swift` (882 LOC) and has five concerns tangled with the generic review surface. This section names **open questions** DMNC-800 must answer while doing its in-place decomposition.

**Manual entry does not use this surface.** The manual path routes directly through `AddMealView`; the staging surface is only reachable from photo / barcode / text paths, which always produce at least one candidate item. There is no empty-state rendering to design.

**Open questions DMNC-800 must resolve in code:**

1. **AI follow-up conversation state** — `followUpHistory`, `isFollowingUp`, `followUpRoundsUsed` currently mutate `stagedItems` from inside the plate UI (`resultsSection`, roughly lines 315-332 and 553-598). Does this state live in a wrapper the caller supplies, or inside the plate?
2. **Inline child navigation** — inline barcode scan (lines 447-471) pushes a `NavigationLink` from inside an item row. A `itemRow: (Binding<Item>) -> ItemRow` closure has no way to coordinate with a parent-scoped navigation destination. Where does this edge live?
3. **Cross-row `@FocusState`** — `focusedItemID: UUID?` coordinates focus across sibling rows. A closure-supplied row cannot naturally share focus state with siblings without an ambient environment value. What's the mechanism?
4. **Batch-meta dependency on items** — portion picker visibility depends on `stagedItems.first?.baseServingG`. A `() -> BatchMeta` closure without `items` access fails this; the closure likely needs `([Item]) -> BatchMeta`.
5. **Store-subscription handlers** — `.onChange(of: store.state.foodAnalysisResult)` handlers inside the staging section are semantically coupled to the plate, not the caller. Do they move into an extracted component or stay at the parent?

**Gate for extraction.** "The shape is clean enough to extract" is not self-assessed. The extraction lands **only if at least three of the five open questions resolve to a shared mechanism** (closure, environment, or binding) that applies identically across the staging-plate's roles — not "caller passes something different each time." If fewer than three resolve that way, ship the in-place decomposition alone and re-raise when a second real consumer (not counting manual entry) appears.

**Deliberately no API sketch here.** An earlier draft included a `struct StagingPlate<...>` signature; reviewers flagged it as commitment-by-accident (anchoring the implementer to a pre-refactor shape). DMNC-800 produces the API from the refactor, documented in the PR description, not from this spec.

## Pattern 2 — Shared primitives for single-object entry

**Purpose.** Three reusable SwiftUI primitives — a numeric field with stepper + tap-to-type, a relative-time picker, and a generic amber chip — that `AddInsulinView` (DMNC-799) uses **directly**, without an intermediate category-wrapping component.

**Decision — no `CategoryPanel` wrapper.** An earlier draft proposed `CategoryPanel<Category, Panel>` generic wrapping a segmented toggle + conditional panel closure. Three reviewers flagged it as renaming plain SwiftUI idioms (`Picker(.segmented)` + `switch` in body) with only one current consumer. Strip the wrapper and nothing of substance remains. We've dropped the wrapper; `AddInsulinView` will use the primitives directly. A second consumer with a category axis can re-raise the wrapper question.

### AmberChip

```swift
struct AmberChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void
    var disabled: Bool = false
    // Minimum tap target: 44×44pt per HIG. Chip grows vertically if needed to meet this floor.
}
```

**Visual states** (explicit tokens, not by-line-citation):

| State | Border | Background | Text |
|---|---|---|---|
| Unselected | `AmberTheme.amber` | `Color.black` | `AmberTheme.amber` |
| Selected | `AmberTheme.amber` | `AmberTheme.amber` | `Color.black` |
| Disabled | `AmberTheme.amberDark` | `Color.black` | `AmberTheme.amberDark` |

**Consumer scope.** AmberChip ships with **two committed call sites** inside DMNC-799's PR: the `InsulinType` row and the `QuickTimeChips` preset buttons. The existing favourites chip at `UnifiedFoodEntryView.swift:95-116` has a different shape (two-line content, conditional `cgaGreen`/`amber` based on `isHypoTreatment`, no selection state) and **stays inline** — it does not adopt AmberChip in DMNC-799. Migrating the favourites chip to a shared component would require either a separate variant (`LabelledAmberChip` with content + optional subtitle + variant color) or a `@ViewBuilder content:` overload; that decision belongs in DMNC-796 (unified entry interactions) or a later design pass, not this spec.

### StepperField

```swift
struct StepperField: View {
    let title: String
    @Binding var value: Double?        // nil = empty field
    let step: Double
    let range: ClosedRange<Double>
    var format: FloatingPointFormatStyle<Double> = .number.precision(.fractionLength(1))
    var autofocus: Bool = false        // if true, TextField grabs focus on appear (default: off)
}
```

**Composition** (not using SwiftUI's native `Stepper`, which requires non-optional `V: Strideable`):

```
[ − ]  [  4.5  ]  [ + ]
         ^ TextField (.decimalPad keyboard); tap to type
```

- The middle `TextField` binds directly to `value: Binding<Double?>` — tapping it shows the decimal pad for direct entry. Empty field = nil.
- `[−]` and `[+]` wrap a proxy Binding that treats `nil` as `0`, applies `step`, and clamps to `range`. Buttons disable when at range bounds. **The TextField and the buttons use different bindings** (direct optional for the field, non-optional proxy for the buttons) to preserve the "empty field" affordance.
- **Revert-on-blur mechanics:** a `@FocusState` tracks the TextField's focus. An out-of-range value committed to the binding (e.g., user types `80` when `range = 0...50`) triggers `.onChange(of: isFocused)` on blur — the view reverts to a `@State var previousValue: Double?` mirror with a brief visual flash (amber border pulse, no alert).

**Default interaction — type-first for insulin dosing.** `AddInsulinView` (DMNC-799) sets `autofocus: true` on the Units field so users land with the decimal pad up and type their dose, matching today's `AddInsulinView.swift:106-111` behaviour. `[−]/[+]` are secondary fine-adjust for correction doses (≤2U where a single tap is faster than typing). This preserves time-to-log for typical 4–12U meal doses (single type) while keeping micro-adjustment available.

### QuickTimeChips

```swift
struct QuickTimeChips: View {
    let title: String
    @Binding var date: Date
    let presets: [TimeOffset]          // required — no default; callers pick presets per feature
}

enum TimeOffset: Hashable {
    case now
    case minutesAgo(Int)               // always non-negative; "minutesAgo(15)" = Date() - 15min
}
```

**Composition:**

```
[ NOW ] [ −15m ] [ −30m ] [ −1h ] [ ⋯ ]
                                    ^ tap opens native DatePicker(.compact) popover
```

- Tapping a preset chip sets `date` and visually marks that chip as selected (via an internal `@State var lastTappedPreset: TimeOffset?` — selection state cannot be derived from `date == presetResolvedDate` because the resolved date diverges from "now" as seconds pass).
- **`.now` semantics (medically significant):** captures `Date()` **at tap time** and stores it. Does not drift with wall clock. A user who taps `NOW` then spends three minutes on the Units field commits the tap-time timestamp, not commit-time.
- **Popover fallback on iPhone.** iOS `.popover(...)` on a button renders as a sheet in compact size class. Acceptable for iPhone; if the sheet fallback proves janky in practice, DMNC-799 can switch to an explicit `.sheet` with `.presentationDetents([.height(280)])`.

**Presets are per-caller (no default).** Insulin uses `[.now, .minutesAgo(15), .minutesAgo(30), .minutesAgo(60)]`. Meal would likely use something tighter like `[.now, .minutesAgo(10), .minutesAgo(30)]` — meal reconstruction from an hour ago is an edge case the product doesn't need to optimise for and would invite stale timestamps that break MealImpact's 2-hour impact window. DMNC-800 picks meal-appropriate presets if and when it adopts QuickTimeChips.

### Illustrative usage — rewritten `AddInsulinView`

```swift
// Type selector — custom amber-chip row (not .pickerStyle(.segmented), which renders system-gray).
HStack(spacing: DOSSpacing.xs) {
    ForEach(InsulinType.allCases, id: \.self) { type in
        AmberChip(
            label: type.shortLabel,
            selected: insulinType == type,
            action: { insulinType = type }
        )
    }
}
.onChange(of: insulinType) { oldType, newType in
    // Field retention: Units and Time persist (both panels use them).
    // Ends resets only when leaving basal (panel-specific field).
    if oldType == .basal, newType != .basal { ends = starts }
}

VStack(spacing: DOSSpacing.md) {
    StepperField(
        title: "Units",
        value: $units,
        step: 0.5,
        range: 0...50,
        autofocus: true                 // matches today's auto-focus behaviour
    )
    QuickTimeChips(
        title: "Time",
        date: $starts,
        presets: [.now, .minutesAgo(15), .minutesAgo(30), .minutesAgo(60)]
    )
    if insulinType == .basal {
        DatePicker("Ends", selection: $ends, displayedComponents: [.date, .hourAndMinute])
    }
    if insulinType == .correctionBolus, (currentIOB ?? 0) > 0.05 {
        IOBStackingWarning(iob: currentIOB ?? 0)
    }
}

// Toolbar Add — fire-and-forget dispatch matches existing pattern for all entry objects;
// failure surfaces through alarm/monitoring paths, not the entry UI.
Button("Add") {
    guard let units else { return }
    store.dispatch(.addInsulinDelivery(starts, ends, units, insulinType))
    dismiss()
}
```

Illustrative only — actual call-site code lands in DMNC-799.

### InsulinType chip order

Chips display in **frequency-based order**: `mealBolus` → `snackBolus` → `correctionBolus` → `basal`. Meal-related types are the most common entries for typical daily use; correction is situational; basal is rare (many users don't use the app for basal at all, they rely on pump automations). This differs from the current `AddInsulinView.swift:28-31` Picker order (correction, meal, snack, basal) — the ordering change is deliberate and lands with DMNC-799. `CaseIterable` conformance on `InsulinType` must declare cases in this order for `ForEach(InsulinType.allCases)` to work without a manual ordering array.

### Prerequisites DMNC-799 must add

- `InsulinType: CaseIterable` — add conformance in `Library/Content/InsulinDelivery.swift` (currently `Codable` only). Declaration order: `mealBolus, snackBolus, correctionBolus, basal`.
- `InsulinType.shortLabel: String` — chip-row tokens (`MEAL` / `SNACK` / `CORR` / `BASAL`). **Not localised** — these are DOS-aesthetic terminal tokens, consistent across locales. (`localizedDescription` remains the localised full-name form; `shortLabel` is a new stable token.)
- `IOBStackingWarning` view — extract from the inline `HStack` at `AddInsulinView.swift:71-78` (icon + caption, amber).

(Note: `AmberChip`, `StepperField`, `QuickTimeChips`, `TimeOffset` are **delivered by DMNC-798** and consumed by DMNC-799 — they are not DMNC-799's own prerequisites. DMNC-799 is blocked by DMNC-798.)

### Category-switch field retention

When the user switches InsulinType mid-entry: **fields present in both panels retain their value; panel-specific fields reset.** Concretely: Units and Time persist across any type switch; Ends (basal-only) resets to `starts` when leaving basal. This preserves partial entries across related categories and avoids surprise data loss.

## Per-feature mapping

| Entry object | Current view (LOC) | Approach | Notes |
|---|---|---|---|
| **Meal** | `UnifiedFoodEntryView` (567) + `FoodPhotoAnalysisView` (882) + `AddMealView` (97) | In-place decomposition first; reusable batch-review component extracted only if the refactor reveals a clean shape (see § Pattern 1 gate). | DMNC-800 does the refactor. Favourite tap = 1-tap direct log (**unchanged**). **Long-press edit dropped** — post-log edit via chart-marker tap remains the supported path. `AddMealView` stays as the edit-existing-entry view (reached from chart-marker / Lists tab, using its existing memberwise-init signature). The post-migration shape of `UnifiedFoodEntryView` is determined by DMNC-800, not this spec. |
| **InsulinDelivery** | `AddInsulinView` (124) | Inline redesign using `StepperField` + `QuickTimeChips` + `AmberChip` (DMNC-799). | Custom amber-chip type row (`mealBolus, snackBolus, correctionBolus, basal` order) + primitives + conditional panels. No category-wrapping component. Auto-focus preserved on Units. Fire-and-forget dispatch matches existing pattern — no error UI. Prerequisites land as part of this PR: `CaseIterable`, `shortLabel`, `IOBStackingWarning`. |
| **BloodGlucose** | `AddBloodGlucoseView` (54) | Direct entry (unchanged). | May later adopt `StepperField` for Int-vs-Double parity once that primitive ships. Deferred. |

## Out-of-scope & follow-ups

**Explicitly out of scope:**

- **Calibration** (`AddCalibrationView`, 96 LOC) — specialised `CustomCalibration` regression-math flow. Stays as-is.
- **Exercise** — HealthKit-imported, read-only.
- **`CategoryPanel` wrapper** — considered and descoped (see § Pattern 2 decision). Re-raise when a second single-object-with-categories consumer appears.
- **Favourite long-press to edit** — dropped. Post-log edit via chart-marker tap (already implemented) is the supported path. Hidden gestures in a medical app are a net negative without user evidence of demand. Long-press semantics across the app belong to DMNC-796.
- **Reusable batch-review component (`StagingPlate`)** — provisional only (see § Pattern 1 gate). Committed API emerges from DMNC-800's in-place refactor, not from this spec.
- **Favourites chip migration** — `UnifiedFoodEntryView`'s QUICK chip row stays inline for now. Migrating it to `AmberChip` requires either a content-aware variant or a different design; defer to DMNC-796.
- **Accessibility specs for the new primitives** — VoiceOver labels, Dynamic Type handling, and tap-target specifics belong in DMNC-797 (micro-interactions polish). Named here so the gap is explicit. **DMNC-798's PR must file or reference a DMNC-797 ticket** covering the new primitives before merging, so the deferral is mechanically honoured (see Success criteria #6).

**Follow-ups:**

- **[DMNC-798](https://linear.app/lizomorf/issue/DMNC-798)** — ships `StepperField` + `QuickTimeChips` + `AmberChip` + `TimeOffset` as shared primitives under `App/DesignSystem/Components/`.
- **[DMNC-799](https://linear.app/lizomorf/issue/DMNC-799)** — rewrites `AddInsulinView` using the primitives inline (custom amber-chip type row, `switch` in body, auto-focus Units, preserved fire-and-forget dispatch). Lands the `CaseIterable` / `shortLabel` / `IOBStackingWarning` prerequisites.
- **[DMNC-800](https://linear.app/lizomorf/issue/DMNC-800)** — in-place `FoodPhotoAnalysisView` decomposition. Resolves the five open questions in § Pattern 1 empirically. Reusable `StagingPlate` extraction only lands if the gate (≥3 of 5 resolve to a shared mechanism) passes.

**Keeping DMNC-798 separate from DMNC-799.** One reviewer argued DMNC-798 has only DMNC-799 as a committed consumer today (symmetric to the `CategoryPanel` abstraction that was correctly dropped) and recommended merging the two PRs. The primitives stay separate because: (a) `StepperField` has a named second consumer in `AddBloodGlucoseView`'s deferred migration; (b) each primitive ships with snapshot tests that are cleaner to review independently of call-site churn; (c) the solo-dev PR review discipline benefits from smaller stacked PRs over one 400-line "new primitives + view rewrite" change. Reasonable people can disagree; the decision is noted here so it doesn't re-emerge at planning time as an unexamined assumption.

## Success criteria

The spec is "done enough" to hand to follow-up implementation planning when all six hold:

1. Every entry object has a clear approach assignment **with rationale** — not just a table cell.
2. `StepperField` + `QuickTimeChips` + `AmberChip` API surfaces are concrete enough that a reviewer can sketch `AddInsulinView`'s rewrite from the signatures alone. Pattern 1's open-questions list is concrete enough that DMNC-800's author knows what to resolve during the in-place refactor.
3. The per-feature mapping names owner view file paths **and** LOC so migration scope is legible.
4. Out-of-scope items have stated reasons + named follow-up Linear issues (DMNC-798/799/800) so nothing is left hanging.
5. Every relationship in the object map is traceable to specific code — **either** as a typed reference (grep the target type's name in the source type's file) **or** as a documented UUID / factory-method convention (the convention is named in the catalog entry itself). Meal↔PersonalFood is the latter (via `analysisSessionId: UUID`, runtime join at `ChartView.swift:735-736`); Meal↔FavoriteFood is the latter (via `FavoriteFood.from(mealEntry:)` + `.toMealEntry()` factories). Explicitly naming the relationship kind prevents aspirational-spec drift without requiring every link to be strictly typed.
6. **Accessibility deferral is mechanically honoured.** DMNC-798's PR description must reference a DMNC-797 ticket (existing or new) scoped to VoiceOver labels, Dynamic Type, and tap-target sizing for the new primitives — otherwise accessibility work silently falls off.

## Decision reversal log

The body of this spec is preserved as-written on 2026-04-23. Reversals surfaced by real-device testing are logged here rather than edited inline, so the original reasoning stays legible alongside what replaced it.

### 2026-04-24 — Favourite tap routing

**Original (spec body, Per-feature mapping, Meal row):** *Favourite tap = 1-tap direct log (unchanged). Long-press edit dropped.*

**Reversed to (DMNC-805, refined on DMNC-805 comment thread):** *Favourite tap → staging plate (pre-populated); press-and-hold → insta-log with a visible countdown / loader that makes the commitment obvious.*

**Why.** TestFlight build 63 testing surfaced that barcode-scanned favourites need a review-before-commit moment (wrong label, wrong carbs, wrong portion) that 1-tap-direct-log bypassed. The hybrid restores a single interaction vocabulary across all Meal paths (tap = staging, everywhere) while preserving a muscle-memory insta-log path via press-and-hold. The loader is the confirmation — no hidden affordance, no accidental commit.

**Implications for follow-up issues.**

- **DMNC-796** — the "Model A vs Model B vs hybrid" tap / long-press semantics question is now resolved in favour of the hybrid. Model B's loading-bar idiom is adopted specifically for the favourite insta-log path; other paths use tap-to-staging.
- **DMNC-800** — scope grows to include (a) routing favourite tap through the decomposed staging surface and (b) a shared `HoldToCommitProgress` sub-component for the insta-log path. The extraction gate for the staging plate itself is unchanged — hold-to-commit is its own primitive.
- **Hypo treatment path (`filterToHypoTreatments`)** — stays 1-tap direct log. Staging during a hypo event is wrong (shaky-hands, urgency, treatment safety floor). Explicitly documented exception.
