---
date: 2026-06-09
topic: settings-improvements
focus: Improvements to the Settings part of the app (App/Views/SettingsView.swift and App/Views/Settings/)
mode: repo-grounded
---

# Ideation: DOSBTS Settings Improvements

## Grounding Context

**Codebase:** DOSBTS — personal CGM iOS app (single developer, TestFlight), SwiftUI + Redux-like architecture, iOS 26, DOS amber CGA aesthetic. Settings = `SettingsView.swift`, a single NavigationStack List with 14 inline sections (~50 settings): Alarms (day/night profiles), Glucose, Insulin, AI, Additional, Bellman, Calibration, Nightscout, AppleExport, SensorConnector (+config), About. Adding one UserDefaults setting = 4–5-file lockstep; AppState holds 65 `didSet` props, UserDefaults has 88 Keys cases; a dedicated `redux-state-coherence-reviewer` agent polices the lockstep.

**Pain points (verified):** single long scroll; mixed numeric inputs (NumberSelectorView / Stepper / TextField / Slider); zero validation for Nightscout URL+secret; Claude key "validation" = `sk-ant-` prefix + length; conditionally hidden controls; no search / export / sync; contrast concerns. **Bug (verified):** `App/Views/SharedViews/NumberSelectorView.swift:57,73` — stepper buttons do `value ± 1`, ignoring declared `step` and bypassing min/max (only the Slider clamps). *Fixed in the DMNC-794 tidy-up.*

**Backlog:** DMNC-794 settings restructure; DMNC-895 boundary threshold-locking. April 2026 ideation: all 7 survivors shipped; rejected then: settings-collapse-into-contextual-controls (too big), glucose-aware DND (overlap argument now stale — day/night shipped).

**Learnings constraining HOW:** no nested sheets (NavigationLink push); settings side effects in middleware, not `.onChange`; reducer-runs-first; secrets via Keychain side channel; day/night schedule changes mirror to App Group + widget boundary timeline entries; GRDB Future early-exits must call promise.

**External prior art:** Dexcom G7 three-layer alarm model (critical floor → named profiles → time-limited Quiet Mode, max 6h) + per-alert "Sample" button + Delay-First-Alert; Libre 3 mandatory urgent-low; Loop FaceID-gates therapy settings; Trio in-settings search (2025); xDrip alarm types vs instances; Gluroo adaptive hiding; Google Authenticator QR transfer; NSUbiquitousKeyValueStore pitfalls → file export safer; aviation FMA "active vs armed" strip; Ableton scenes; `show running-config` dumps; cockpit pre-flight checklists.

**Session mechanics:** 6 frames × ~8 ideas = 49 raw candidates → orchestrator critique → 7 survivors. Strongest convergence: credential validation (all 6 frames), settings export (4), Quiet Mode (4), search (3), unified numeric input (3), settings-change journal (3).

## Topic Axes

1. Structure & navigation
2. Alarm safety & profiles
3. Integrations & credentials
4. Settings data lifecycle
5. Input & feedback components

## Ranked Ideas

### 1. Live credential verification everywhere ("TEST CONNECTION")
**Description:** Uniform credential treatment across Nightscout, Claude API key, LibreLinkUp: explicit test action with a real round-trip (Nightscout `/api/v1/status`, lightweight Anthropic call), inline OK / AUTH FAIL / UNREACHABLE + last-success timestamp, self-healing status (middleware downgrades validity on first runtime auth failure). Sub-feature: paste full Nightscout URL with embedded token, parse credentials out. Extract a reusable `CredentialField`.
**Axis:** Integrations & credentials
**Basis:** `direct:` NightscoutSettingsView dispatches raw strings with zero validation; AISettingsView:145-148 validation is `hasPrefix("sk-ant-") && count > 20`, never downgraded at runtime; connections index shows green for non-empty-but-wrong secrets. `external:` network-gear "Test Connection" convention.
**Rationale:** All 6 ideation frames independently produced this. Misconfigured credentials fail silently at use-time; the good pattern half-exists one section away.
**Downsides:** Network/token cost per test; per-integration middleware; offline vs auth-fail must render distinctly.
**Confidence:** 95% | **Complexity:** Low-Medium | **Status:** Unexplored

### 2. Three-layer alarm model: visible critical floor + Quiet Mode override
**Description:** (a) Surface the existing critical-low breakthrough (`isCriticalLow`, `alarmLow − 15`) as a visible locked row; (b) time-boxed "QUIET FOR 1h/2h/4h (max 6h)" suppressing non-critical alarms, auto-expiring, never mutating profiles, critical breaks through. Extension: per-profile alarm sounds (xDrip type/instance split).
**Axis:** Alarm safety & profiles
**Basis:** `direct:` `max(dayAlarmVolume, nightAlarmVolume)` EOL-warning defense proves zeroing-night-volume is a known hazard; snooze machinery with breakthrough exists. `external:` Dexcom G7 Quiet Modes + critical floor; Libre 3 mandatory urgent-low.
**Rationale:** Removes the incentive for the dangerous workaround the code already defends against; mostly composition of existing primitives. Resolves the stale April "glucose-aware DND" rejection.
**Downsides:** Third suppression concept needs crisp precedence in GlucoseNotification; widget/Live Activity should reflect quiet state.
**Confidence:** 90% | **Complexity:** Medium | **Status:** Unexplored

### 3. Settings export/import — DOS-style config dump
**Description:** EXPORT CONFIG renders all UserDefaults-backed settings as monospace `KEY = VALUE` text (`show running-config` aesthetic), shareable .txt, secrets redacted to `[KEYCHAIN]`. IMPORT replays as actions through the reducer. Optional QR transfer.
**Axis:** Settings data lifecycle
**Basis:** `direct:` no export/import/sync; TestFlight reinstalls wipe ~50 hand-tuned values; Keychain rule defines redaction boundary. `external:` SYSGEN/`show running-config`; Google Authenticator QR; NSUbiquitousKeyValueStore rejected (silent conflict loss).
**Rationale:** Four frames converged; reinstall amnesia is personally felt pain; Redux makes restore literally "dispatch this list"; the most on-brand export possible.
**Downsides:** Import needs versioning vs renamed keys; secrets re-entered manually; mg/dL vs mmol/L conversion edge cases.
**Confidence:** 90% | **Complexity:** Low-Medium | **Status:** Unexplored

### 4. In-settings search
**Description:** Monospace amber search field atop SettingsView filtering all sections by label/keyword (stretch: current value). Results navigate into the owning section.
**Axis:** Structure & navigation
**Basis:** `direct:` 14 inline sections, no `.searchable`; hidden conditional controls make settings hard to find. `external:` Trio shipped settings search 2025 at this complexity class.
**Rationale:** Cheapest meaningful answer to the #1 pain point; survives any future IA (including the DMNC-794 drill-down hub).
**Downsides:** Label→section index must not drift (hand-built unless #7 exists); hidden matches need reveal behavior.
**Confidence:** 85% | **Complexity:** Low | **Status:** Unexplored

### 5. Safety command deck: active-profile strip + pre-flight check
**Description:** (a) FMA-style persistent strip atop Alarm settings: `NOW: NIGHT · LOW 70 · HIGH 200 · VOL 20% · FLIPS TO DAY 07:00`; (b) runnable "PRE-FLIGHT CHECK" walking fixed invariants (notification permission, night-volume audibility, night-vs-day permissiveness, API key reachable, Nightscout responding, sensor paired) with green/amber/red lines. Extension: Siri "What are my alarm settings?" readback on build-94 App Intents rails.
**Axis:** Alarm safety & profiles
**Basis:** `direct:` alarm accessors resolve via `activeAlarmProfile` but status is never surfaced; DMNC-895 confusion is partly visibility; warnings exist but passive/scattered. `external:` aviation FMA; cockpit checklists.
**Rationale:** Collapses configuration/status divide for the most safety-critical subsystem; "am I protected tonight?" becomes one glance.
**Downsides:** Vertical space; async probes per checklist item; red-status fatigue if too strict.
**Confidence:** 85% | **Complexity:** Medium | **Status:** Unexplored

### 6. Evidence-based alarm tuning: volume-envelope bracket + would-have-fired counts
**Description:** (a) Sound preview bracketed across day/night/breakthrough volumes, labeled, decoupled from the picker's commit side effect; (b) while editing a threshold, show "last 7 days would have alarmed N times" computed in middleware from GRDB history.
**Axis:** Input & feedback components
**Basis:** `direct:` previews play at day volume only (footer admits it); sound bindings fire `testSound` in the setter (preview = commit); glucose history exists. `external:` Dexcom Sample button; photography exposure bracketing.
**Rationale:** Current preview hides the silent-night trap — the exact failure the EOL logic works around; would-have-fired turns abstract mg/dL into observed consequences.
**Downsides:** Longer audio interaction; efficient history scan + honest wording needed; count must respect profile schedule.
**Confidence:** 80% | **Complexity:** Medium | **Status:** Unexplored

### 7. Registry-driven settings engine (collapse the 4-file lockstep)
**Description:** Make settings a first-class `SettingDefinition` registry (key, type, default, section, label, keywords, availability predicate) — macro or table — synthesizing persistence, accessors, generic reducer handling. Derivatives fall out: search index, export/import serialization, settings-change journal (audit + 24h undo + per-section reset), section manifest, ordered idempotent migration runner (replacing one-off `hasMigratedAlarmProfiles` gates). UI half: typed-row library (channel-strip numeric component, credential field, toggle row).
**Axis:** Settings data lifecycle
**Basis:** `direct:` traced `showScanlines` across 5 files; 65 `didSet` props / 88 Keys cases; a dedicated coherence-reviewer agent polices the lockstep. `reasoned:` search/export/audit/reset are all functions over a set that exists only implicitly across 5 files; reify once, four features become cheap.
**Rationale:** Highest leverage — changes the unit economics of every other survivor and every future setting; 138-test suite can pin the refactor.
**Downsides:** Highest cost/risk; macro is a serious lift (table cheaper first); must be incremental; infrastructure-before-features trap if derivatives aren't built.
**Confidence:** 70% | **Complexity:** High | **Status:** Unexplored

## Rejection Summary

| # | Idea | Reason Rejected |
|---|------|-----------------|
| 1 | BIOS Setup screen IA (paged categories, dot-leaders, help bar) | Best as the dedicated DMNC-794 brainstorm — strongest IA candidate seen, too big to rank here; search delivers findability now without precluding it |
| 2 | Named alarm profiles beyond day/night (memory channels) | Quiet Mode covers temporary states at a fraction of the migration cost just paid; revisit on demand |
| 3 | Transactional Save & Exit settings buffer | Staged-commit fights iOS immediate-apply idiom; journal+undo gives recovery cheaper |
| 4 | Friction tiers / FaceID gate for therapy settings | Single-user app; post-hoc undo beats pre-commit ceremony |
| 5 | Infer night window from iOS sleep schedule | Basis fails: iOS exposes recorded sleep samples, not the configured schedule; too noisy for a safety window |
| 6 | Context-prune Insulin/IOB sections (Gluroo) | User demonstrably doses daily — solves a multi-user problem this app doesn't have |
| 7 | DirectConfig flag cleanup | Mechanical chore — file directly |
| 8 | Basal DIA named-insulin picker | Solid quick win, below survivor bar; file as small issue (template: bolus preset picker) |
| 9 | Stable disclosure (dimmed-not-hidden dependent controls) | UX polish — **addressed by the DMNC-794 tidy-up (Phase B of the 2026-06-10 plan)** |
| 10 | Cheat-code reveal of hidden sections | Novelty exceeds utility; search + stable disclosure solve it |
| 11 | Settings-change journal standalone | Absorbed into #7 as derivative; shippable standalone if registry deferred |
| 12 | Siri alarm-settings readback | Folded into #5 as the voice surface |
| 13 | Per-profile alarm sounds (type/instance split) | Folded into #2 as extension |
| 14 | Nightscout paste-URL autoconfig | Folded into #1 as sub-feature |
| 15 | Section manifest / migration runner | Folded into #7 as components |
| 16 | "Settings as queryable Redux state-dump" | Duplicates #4 + #7 framing |

All five axes have at least one survivor; no coverage gaps.

## Session Log
- 2026-06-09: Initial ideation — 49 candidates across 6 frames, 7 survived. Sources: codebase scan, 11 institutional learnings, web research (Dexcom/Libre/Loop/Trio/xDrip/Gluroo + cross-domain), April 2026 ideation (all 7 survivors shipped). Bug found + verified: NumberSelectorView ignores step/min/max.
- 2026-06-10: User chose the "tidy up settings" direction → DMNC-794 drill-down hub + consistency plan executed (NumberSelectorView fix, stable disclosure, 6-category hub). Rejection #9 addressed; survivors #1–#7 remain Unexplored.
