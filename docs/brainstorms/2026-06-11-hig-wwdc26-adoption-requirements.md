---
date: 2026-06-11
topic: hig-wwdc26-adoption
---

# HIG / WWDC 2026 Adoption — entry-surface quality, persistent status bar, on-device AI

## Summary

Two tracks now, one deferred. Track A: a surface-quality pass over the entry/log screens — Apple interaction grammar wearing DOS amber visuals, a shared meal-item component, a new brighter secondary-text token, and the ASK AI multi-tap bug fixed. Track B: a persistent glucose + log-actions bar above the tab bar on every tab — shipped additively first, with Overview's buttons removed only after the bar passes a hypo-ergonomics gate. Track C (deferred to Linear DMNC-1023): on-device Apple Intelligence via the provider-swap architecture.

## Problem Frame

Entry surfaces diverged as features shipped: insulin entry uses the primitives-based Apple grammar in DOS visuals, while manual meal, blood glucose, and calibration forms still render system-styled (gray) — the app feels like two apps. The OOUX doc (`docs/brainstorms/2026-04-23-ooux-catalog-and-entry-patterns-requirements.md`) pinned the identity bet — consumer-iOS interaction grammar, DOS visual layer — but it is unevenly enforced. Separately: Overview's INSULIN/MEAL buttons sit behind the Liquid Glass tab bar (a confirmed layout bug); glucose and log actions vanish when switching tabs; small dim-amber text fails WCAG AA (`amberDark` measures 3.74:1 on black); and the ASK AI search row needs 3–4 taps to open. WWDC 2026 (June 8) shipped the APIs that make the deferred AI track concrete.

## Key Decisions

- **The insulin screen is the reference model.** Apple interaction grammar + DOS visual skin. All entry surfaces converge on it; the OOUX identity bet is the governing rule. System-rendered chrome (picker internals, keyboard, menus) is exempt from the visual requirement — see R1.
- **Settings screen content and the native tab bar chrome are untouched.** The user likes both as they are. The persistent bar appears above the tab bar on all tabs *including* Settings (R7) — that bar is new chrome, not a Settings change.
- **Track B is phased, with a named fallback.** The themed-accessory spike (R7a) gates everything; the bar ships additively; Overview's buttons are removed only after the hypo-ergonomics gate (R9). If the accessory can't carry DOS theming, the fallback is a custom `safeAreaInset` bar. The tab-bar overlap bug is fixed immediately by padding either way — the bug fix is not hostage to the bar.
- **Meal item is a first-class component with per-context variants.** One component, documented variants for recents and Lists; pixel-identical rendering across contexts is explicitly not the goal.
- **Caption legibility ships as a new token, not a sweep.** `amberDark` keeps its dimming/disabled role; informational secondary text migrates to a new, AA-compliant token after a role audit. Hierarchy subordination moves to size/weight where brightness no longer carries it.
- **Local AI is researched-then-parked** (Linear DMNC-1023, High). The toggle gates the *new* on-device/PCC path; the Claude path stays byte-for-byte intact. Text-only parsing on the iPhone 15 Pro under iOS 26 is a possible early slice — pursuing it is deferred to Track C planning.

---

## Requirements

**Track A — entry-surface quality**

- R1. Developer-themable surfaces on all add/edit entry screens (manual meal, blood glucose, calibration, staging plate — insulin is the migrated reference) render in DOS visuals: black background, amber palette, monospace type, sharp corners. Exempt: system-rendered chrome (picker wheels/calendar internals, keyboard, context menus) — `.tint` is applied where the API permits.
- R1a. DOS-styled replacements for system form controls keep the system's accessibility floor: ≥44pt tap targets, VoiceOver labels equivalent to the system control's defaults.
- R2. Interaction patterns follow Apple grammar: native pickers, steppers, standard navigation and focus behavior; no custom gestures beyond the established hold-to-commit.
- R3. The meal item becomes one shared component with documented per-context variants, replacing the bespoke rows in the recents list and Lists tab. The digest timeline (today a flat text label, not a row) adopts it only if planning decides the timeline's restructure is worth it — otherwise it stays compact text and is named out of scope.
- R4. `docs/design-system.md` gains a component-standard section (no sibling doc): layout, type scale, color roles, tap-target rules, written as a checklist new-component PRs self-certify against.
- R5. A new secondary-text token (AA-compliant, ≥4.5:1 on black) is introduced for informational captions. Preconditions: (a) audit every `amberDark` call site and classify informational-text (migrate) vs intentional dimming/disabled (keep); (b) verify the stale-data warning and other semantic-amber surfaces keep their salience after migration; (c) update the widget's parallel token (`WidgetDesignSystem.swift`) in tandem for migrated text roles. `amberDark` itself is not mutated.
- R6. Tapping the ASK AI row in food-entry search results navigates on the first tap regardless of keyboard state, and the query starts executing on navigation (not on a further user action). Root cause is unknown — investigate before fixing. Keyboard dismissal behavior and whether the search text is preserved on return are decided during that investigation (see Outstanding Questions).

**Track B — persistent status bar (phased)**

- R7. A bar above the tab bar shows the current glucose value (with trend) and Meal + Insulin log actions on every tab, Settings included, using the native tab-bar accessory pattern (iOS 26 API; no iOS 27 bump). Content priority when space is constrained: glucose value never truncates → action buttons → trend arrow drops first. Layout is specified for both accessory environments (`.inline` and `.expanded`).
- R7a. **Gating spike:** prototype the accessory with black background + amber monospace content on device/simulator before any other Track B work. If the Liquid Glass capsule can't carry the DOS look, Track B switches to a custom `safeAreaInset` bar (plain black, amber text, sharp edges) — requirements R7–R10 apply to it unchanged.
- R7b. Bar state inventory — the bar renders a defined treatment for each state, in both accessory environments:

  | State | Bar shows |
  |---|---|
  | No sensor paired | "NO SENSOR" + log actions (actions always work) |
  | Sensor, no reading yet | placeholder glyph + log actions |
  | Fresh reading (≤5 min) | value + trend, amber |
  | Stale 5–14 min | value + "X MIN AGO", amber warning treatment (mirrors hero) |
  | Stale 15+ min | same, red treatment (mirrors hero) |
  | Treatment cycle active | countdown indicator replaces trend; MEAL routes per R8 |
  | Alarm firing | bar mirrors the alarm color state; never obscures the alarm UI |

  The bar reads the same state the hero reads (one source, no copy, no separate refresh path), and never collapses/minimizes while a treatment cycle is active.
- R8. The bar's MEAL action routes conditionally: hypo-filtered entry sheet when a treatment cycle is active, the normal entry sheet otherwise. This conditional is **new behavior** — today's Overview MEAL button always opens the normal sheet and the hypo variant is only reachable via the treatment modal. INSULIN opens the existing insulin sheet.
- R8a. A single app-level presentation root owns all entry/treatment sheets. The `ActiveSheet` enum, `pendingSheet` sequencing, and the treatment-prompt/recheck observers move from OverviewView to the root (ContentView scope) so the bar can present from any tab without creating a second presentation root (the sibling-sheet collision class is documented in `docs/solutions/ui-bugs/swiftui-nested-sheets-present-wrong-view-20260316.md`).
- R9. **Phase 1:** the bar ships additively; Overview keeps its INSULIN/MEAL buttons with the tab-bar overlap fixed via safe-area padding. **Phase 2:** the buttons are removed only after the hypo-ergonomics gate passes: bar log actions are ≥44pt, the bar never minimizes during a treatment cycle, and at least one real dogfooding cycle confirms no hesitation or mis-taps. When the buttons go, Overview's chart may expand into the reclaimed space; the bar's safe-area contribution is accounted for so no content sits beneath it.
- R10. (Merged into R7b — staleness is part of the bar state inventory.)

**Track C — on-device AI (deferred; lives in Linear DMNC-1023)**

- R11. DMNC-1023 carries the WWDC findings and intended shape: one session interface with swappable backends — on-device Foundation Models → Private Cloud Compute → existing Claude key — user-toggleable, Claude path untouched until then.
- R12. The issue's constraints are dated ("as of iOS 27 beta 1, 2026-06-08") and its first task is re-verifying them against the then-current beta/RC: image input tier (12 GB devices), provider protocol + PCC availability, the iOS 26 text-only early slice, and testing options (borrowed 17 Pro or Mac simulator).

---

## Key Flows

- F1. **Log from anywhere.** User on the Digest tab → glances at the bar → taps MEAL → food-entry sheet opens (presented by the root, R8a) → logs → returns with the bar updated. **Covers R7, R8, R8a.**
- F2. **Hypo while in Settings.** Treatment cycle active → bar shows countdown state → user taps MEAL → hypo-filtered sheet opens. **Covers R7b, R8.**
- F3. **First-tap AI.** User types "two scrambled eggs" in food search → taps ASK AI once → navigation happens immediately → analysis screen shows its loading state while the query runs. **Covers R6.**

## Acceptance Examples

- AE1. Open Add Blood Glucose: every developer-themable surface is black/amber/monospace; only system chrome (keyboard, picker internals) may render system materials. **Covers R1.**
- AE2. With a treatment cycle active, the bar's MEAL action on any tab opens the hypo-filtered variant; without one, the normal sheet. **Covers R8.**
- AE2a. A treatment prompt fires while a bar-opened sheet is up on a non-Overview tab: exactly one presentation root resolves it — no wrong-sheet, no dropped prompt. **Covers R8a.**
- AE3. The new secondary-text token measures ≥4.5:1 against #000000; a disabled Settings control still renders visibly dimmer than adjacent enabled text. **Covers R5.**
- AE4. The meal component renders in recents and Lists as its documented per-context variants — same component, not necessarily identical pixels. **Covers R3.**
- AE5. With the keyboard up, the first tap on ASK AI navigates; the query is already running when the analysis screen appears. **Covers R6.**

## Scope Boundaries

- Settings screen content and native tab bar chrome — unchanged (user preference; the bar above them is additive).
- The Claude analysis path — byte-for-byte preserved until Track C ships.
- No iOS 27 target bump in this wave.
- Digest timeline meal rendering — stays compact text unless planning explicitly takes the restructure (R3).

### Deferred for later

- Track C implementation (DMNC-1023; revisit on 12 GB hardware or iOS 27 release).
- Overview button removal (R9 Phase 2) until the hypo-ergonomics gate passes.
- iOS 27 niceties from research (landscape Dynamic Island, Watch Smart Stack forwarding, extra-large widgets, `Tab(role: .prominent)`) — own ideation later.

## Dependencies / Assumptions

- **R7a spike risks, named:** ContentView nests its TabView inside `LoadingView` (GeometryReader/ZStack), which can break `tabViewBottomAccessory` preference propagation — the TabView likely needs to become the outermost view. The global `UITabBar.appearance().configureWithOpaqueBackground()` override may also fight the capsule's glass rendering. Both are part of the spike's checklist.
- The accessory pattern remains current in iOS 27 (research, 2026-06-08).
- `amberDark` contrast measured at 3.74:1 — the legibility complaint is objective, not taste.

## Outstanding Questions

**Deferred to planning**

- New secondary-text token value and name (and which DOSTypography roles pair with it).
- Whether the bar collapses with `tabBarMinimizeBehavior` outside treatment cycles (never during one, per R7b).
- ASK AI: root cause; keyboard dismissal as part of the tap response vs carried into the transition; search text preserved or cleared on return.
- Whether the digest timeline takes the meal component (R3 fork).

## Sources

- `docs/brainstorms/2026-04-23-ooux-catalog-and-entry-patterns-requirements.md` — identity bet, object catalog.
- WWDC 2026 research (2026-06-11): Foundation Models image input + device tiers ([Session 241](https://developer.apple.com/videos/play/wwdc2026/241/)), PCC developer access ([Session 319](https://developer.apple.com/videos/play/wwdc2026/319/)), `LanguageModel` provider protocol + Anthropic package ([Session 339](https://developer.apple.com/videos/play/wwdc2026/339/)), [`tabViewBottomAccessory`](https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(isenabled:content:)/), [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass).
- Code grounding (doc review, 2026-06-11): sheets are private `@State` on `App/Views/OverviewView.swift` (`ActiveSheet`/`pendingSheet`); `App/Views/ContentView.swift` wraps TabView in `LoadingView` and sets opaque `UITabBarAppearance`; system-styled Forms confirmed in `App/Views/AddViews/{AddMealView,AddBloodGlucoseView,AddCalibrationView,FoodPhotoAnalysisView}.swift`; digest timeline meals are flat labels in `App/Views/DigestView.swift`; `amberDark` ≈3.74:1 with a parallel widget token in `Widgets/WidgetDesignSystem.swift`.
