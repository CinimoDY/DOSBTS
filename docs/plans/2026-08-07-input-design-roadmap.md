# Input & Design Roadmap — 2026-08-07

**Umbrella:** DMNC-1480 · brainstormed + decomposed 2026-08-07 from Dom's post-Build-133 dogfooding notes. Verbatim idea capture lives in the umbrella issue. This doc is the shared context for each item's later deep-planning session — read it before planning any child issue.

Vision choices confirmed with Dom in-session: badges = **chart marker chips**; voice V1 = **in-app mic**; notes V1 = **Digest-AI only**; order = **design track first**.

## The vision, in one pass

- **Voice becomes the primary logging mode**: say "I'm eating this", optionally point the camera or scan a barcode mid-flow, and the AI resolves the food into the app's own database. Quantities are conversational — "100 mL", "a cup" — with the AI converting colloquial units, and eventually *personal* portion presets ("my mug = 300 mL", "specify your kind of chunks").
- **The app remembers every food ever logged**, not the last 20; autocomplete/search reaches arbitrarily far back.
- **Glucose doesn't happen in a vacuum**: illness, stress, sluggishness get journaled and the AI analysis consumes them.
- **Figma is the design conversation medium**: Dom marks up frames, Claude reads and implements.
- Two immediate irritations: the overlapped DISCONNECT chip; cleaner marker chips.

## Work items

| # | Issue | Title | Size | Status |
|---|-------|-------|------|--------|
| 1 | DMNC-1481 | fix(overview): DISCONNECT chip overlap (SensorLineView) | S | **ready for worker** — ship next build |
| 2 | DMNC-1482 | Figma: refresh + extend DOSBTS_fig | M | **blocked on Dom** (file confirm + figma-console MCP) |
| 3 | DMNC-1483 | design(chart): marker chip cleanup via Figma | S–M | blocked by DMNC-1482 |
| 4 | DMNC-1484 | feat(food): history depth — A1 search now, A2 catalog later | M | A1 near-ready; A2 needs pipeline |
| 5 | DMNC-1485 | feat(journal): notes V1 — capture + Digest AI | M | needs pipeline |
| 6 | DMNC-1486 | feat(voice): in-app mic V1 — dictation into AI food path | L | needs pipeline (ce-brainstorm first) |

### 1. DISCONNECT chip overlap — root cause verified

`App/Views/Overview/SensorLineView.swift:23-38`: status label and reveal-on-tap DISCONNECT chip are ZStack siblings; the label's hard-coded 86pt reservation is ~10pt narrower than the rendered chip (~96pt). Fresh-sensor labels (`CONNECTED · 13d 21h LEFT`) overlap; unclamped Dynamic Type amplifies. Regression from `68e51c19`. **Fix:** measure the chip (PreferenceKey) and derive the reservation — do NOT restructure to HStack (optically-centered label is a documented design, `SensorLineView.swift:14-22`) and do NOT bump the constant (that's the regression class). Verify all three chip states + fresh-sensor label + xxxLarge type.

### 2. Figma — refresh + extend, NOT greenfield

DMNC-976 (Done, June) already built **`DOSBTS_fig`** (key `1Hemp6DehvK1a5uMrPJyhr`): 37-var amber collection, DOS components (incl. Event Marker Lane, Glucose Hero, Glucose Chart), 4 screens — via figma-console MCP; figcli pipeline in eiDotter (`figcli/DOSBTS.design.md`, PR eiDotter#360). The file is ~Build-100 era; the app is at 133 (status bar, marker-lane rework, digest infographic, Ratio Lab since). Scope: refresh the 4 screens, extend to food entry/staging plate + Log, establish the markup→read→implement→screenshot round-trip. **Dom unblocks:** confirm the file, reconnect the figma-console MCP. (The built-in `DesignSync` tool targets claude.ai/design, not Figma.)

### 3. Marker chips — design conversation on the existing Figma component

Scope = the event-marker-lane chips only (`Library/Content/EventMarker.swift` `chipRows` + `EventMarkerLaneView.FlagView`). Constraints for the conversation: ≤3-row/60pt invariant pinned by `MarkerChipRowTests`; `c`/`b` suffixes are a deliberate DMNC-715 decision; width changes must update `estimatedChipWidth` and preserve DMNC-1415 zoom-aware consolidation. Adjacent: DigestView timeline renders insulin cyan — inconsistent with the lane's amber family.

### 4. Food history — two complementary lanes

**A1 (first):** the ~20 cap is `LIMIT 20` in `getRecentMealEntries()` (`FavoriteStore.swift:333-344`); search filters those 20 in memory only (`UnifiedFoodEntryView.swift:420-425`). `MealEntry` = complete never-pruned history, full macros, index already exists. Add `searchMealEntries(matching:limit:)` + action/state; search falls through to DB; raise/paginate recents.

**A2 (after voice V1, so real phrasing informs it):** promote `PersonalFood` (today: AI-corrections-only, carbs-only, 90d/200-row prune, 12-row AI context) into the first-class catalog — macros + `source` + `useCount`, upsert from every log path, recency+frequency ranking serving autocomplete AND the AI dictionary. **"Chunks" lands here:** extend the shipped global `ServingPreset` system (DMNC-562, alive in `Library/Content/ServingPreset.swift` + 4-file state) to per-food presets + AI-prompt awareness. Risks: corrections+upsert transaction & glycemic-score linkage (meal-impact regression surface); name canonicalization under the NOCASE unique index; prune relaxation vs prompt-size economics.

### 5. Notes/journal — greenfield, V1 = capture + Digest AI

No note-like anything exists (verified; Nightscout ignores `notes` both directions). V1: `NoteEntry` (timestamp, free text, ≤1 optional tag from a small closed set) via 3-file GRDB pattern + `NoteStore` middleware (`.active`-guarded, BOTH App.swift arrays); capture via Log tab + SheetCoordinator case (never a local `.sheet`); feed via `notes` on `DailyDigestEvents` (`DailyDigest.swift:64-68`) → capped `<notes>` section in `buildDigestPrompt` (`ClaudeService.swift:370-435`). Deferred: chart-lane markers, meal-impact confounder flagging (V1.5 — needs `isClean`-reason schema), clinic report, Nightscout, voice-dictated notes. Decide in planning: prompt cap, `aiConsentDailyDigest` copy update, tag set, edit/backdate, retention.

### 6. Voice V1 — in-app mic

Supersedes DMNC-559's cancellation ("voice via Wispr Flow externally") and the Wispr line in `docs/references/food-logging-2026-vision.md:79` (update the doc when this lands). Zero STT code today; `ReadAloud` is output-only. V1: reusable dictation control + `SpeechService` under `App/` (never `Library/`), on-device `SFSpeechRecognizer` (offline-first); transcript in `@State` (follow-up-field precedent, not Redux); committed text into the two existing sinks: search field → ASK AI `.analyzeFoodText` (multi-turn, consent-gated) and staging-plate follow-up field. Quantities lean on Claude's existing parsing; presets are A2, not a dependency. Also: two Info.plist keys (mic + speech recognition); audio-session coexistence with ReadAloud. Deferred: hands-free guided session (TTS speaks back — the full vision), Siri/App-Intents upgrade (`AddMealIntent` bypasses Redux + AI), dictated notes. Decide in planning: on-device fallback policy, commit semantics, session ownership, simulator testing strategy, auto-dispatch vs confirm.

## Sequencing

```
now:       [1481] disconnect fix  → ship next build
Dom-gated: [1482] Figma refresh   → the moment Dom confirms file + reconnects MCP
then:      [1483] chips (via Figma) → [1484-A1] history search → [1485] notes V1
           → [1486] voice V1 → [1484-A2] catalog + chunks
```

Coordination notes: 1484-A1 and 1486 both touch the `UnifiedFoodEntryView` search field — coordinate if concurrent; 1484-A2 and 1485 both grow the ClaudeService prompt — shared budget; 1485 is fully independent and can slot anywhere.

## Process

Per-item: planning pipeline (ce-brainstorm where product shaping remains → ce-plan → ce-doc-review → revise) → hand-off via conductr to fresh worker sessions → PR review → CHANGELOG `[Unreleased]` entry rides each PR. DMNC-1481 skips straight to a worker brief; DMNC-1484-A1 likely can too.
