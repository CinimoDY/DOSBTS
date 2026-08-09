# Voice Input V1 — Design Options

**Issue:** DMNC-1486 · **Umbrella:** DMNC-1480 · **Date:** 2026-08-09
**Status:** DECISION DOC. Not a plan. Read section 3, answer six either/ors, then this becomes a plan.
**Scope frozen upstream:** in-app mic. Not hands-free dialog. Not Siri/App Intents. Those are later phases and are listed in §6.

## Intent contract (verbatim)

> "The mode of input we should really build for the DOSBTS is voice input, easily saying, 'I'm eating this,' and then having the scan barcode or take picture. That request is set up by AI in the database and then able to quantify, 'Okay, that's 100 mL,' or 'I got 100 mL,' and then say, 'Okay, a cup is so and so many mL.' Specify your kind of chunks."

Three separable asks live in that quote. Only the first is V1.

| Ask | Where it lands | Status |
|---|---|---|
| "easily saying 'I'm eating this'" | **This doc.** Get spoken words into a `String`. | V1 |
| "then scan barcode or take picture" | Partly already shipped (§0). Voice+photo *fusion* is new. | Split — see §0 and §6 |
| "a cup is so and so many mL" / "specify your kind of chunks" | Already half-shipped (§0). Personal presets = **DMNC-1484-A2**. | Not a V1 dependency |

---

## 0. What is already true (read this before designing anything)

**The quantity intelligence the user is asking for already ships.** `App/Modules/Claude/ClaudeService.swift:220-232` contains a `<resolution_protocol>` block that already maps informal quantities:

```
- Metric quantities (200ml, 100g): use as stated.
- Informal quantities: "a couple" = 2, "a few" = 3, "a handful" of nuts = 28g,
  "a slice" of bread = 28g, pizza = 100g, "a cup" = 240ml liquid.
```

**Consequence: V1 writes zero unit-parsing code.** "100 mL" and "a cup" already resolve correctly today via typed text. Voice only has to produce the words. The *personal* half ("my mug = 300 mL") is the `ServingPreset` extension in DMNC-1484-A2 and is deliberately downstream.

**"Say it, then scan" is half-built.** The staging plate already has per-item barcode rescan — `FoodPhotoAnalysisView.swift:462-471` wires `onBarcodeRescan` → `scanTargetID` → `ItemBarcodeScannerView`. So *speak → ASK AI → staging plate → tap an item → SCAN* works end-to-end the moment voice fills the field.

**"Say it, then shoot" is genuinely absent.** `ClaudeService.analyzeFood(imageData:thumbWidthMM:personalFoods:recentCorrections:)` (`:25`) takes **no user text**, and `buildPhotoPrompt` (`:256`) is a fixed string. Merging a spoken note with a photo in one request needs a new service method. That is the highest-desire deferred item — §6, D-3.

**Two drop-in `String` sinks exist.** Both are plain text fields; nothing downstream cares how the characters arrived:
- Search field → ASK AI button → `.analyzeFoodText(query:)` — `UnifiedFoodEntryView.swift:342-406`. Note the comment at `:366-372` explaining why that is a `Button` and not a `NavigationLink`; do not "fix" it.
- Staging-plate follow-up field → `.analyzeFoodText(query:history:)` — `FoodPhotoAnalysisView.swift:604-639`, capped at 3 rounds / 4000 chars.

**Doc debt.** `docs/references/food-logging-2026-vision.md` carries the reversed Wispr Flow decision in **two** places, not one: line **17** ("Voice side-car: IN PROGRESS (Wispr Flow + NL text parsing, DMNC-558)") and line **79** ("| Voice via Wispr | DMNC-558 | Planned (external tool) |"). Fix both in the implementing PR.

**Constraints inherited.** `UIApplication.shared` is extension-unavailable → mic/speech code lives under `App/`, never `Library/`. `App/Info.plist` has camera/NFC/Bluetooth/Calendar/HealthKit strings but **no** `NSMicrophoneUsageDescription` and **no** `NSSpeechRecognitionUsageDescription`. It *does* already declare `UIBackgroundModes: [audio, bluetooth-central]` (`Info.plist:67-71`) — that matters, see R1/R5.

---

## 1. The API landscape

### What I verified today vs what I am assuming

**Verified** (web research, 2026-08-09; sources at the end of this section):
- `SpeechAnalyzer` + `SpeechTranscriber` + `DictationTranscriber` + `SpeechDetector` exist, are **iOS 26+ only**, run on-device, and are `AsyncSequence`-based. `DictationTranscriber` is the documented fallback for devices/locales `SpeechTranscriber` does not cover, and uses the same model as `SFSpeechRecognizer`'s on-device path.
- **`SFSpeechRecognizer` is NOT formally deprecated.** It ships and works in iOS 26.
- `SFSpeechRecognizer` limits (Apple Technical Q&A **QA1951**): **1 minute of audio per request**, and **1,000 requests per hour per device** — a device-wide quota shared with every other app, not per-app.
- `supportsOnDeviceRecognition` exists since iOS 13; `requiresOnDeviceRecognition = true` forces local inference but the model must already be downloaded.
- `contextualStrings` (~100 short phrases) biases `SFSpeechRecognitionRequest`. **`SpeechTranscriber` (long-form) does not accept contextual strings** — a real gap.
- `AssetInventory` governs the new API's models: `supportedLocales` vs `installedLocales`, `assetInstallationRequest(supporting:)`, a cap on concurrently allocated locales, and models are *shared system assets the OS may delete under disk pressure*.
- `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)`; transcriber option `.volatileResults`; results carry `isFinal`.
- `AVAudioSession.requestRecordPermission(_:)` is deprecated since iOS 17 → use `AVAudioApplication.requestRecordPermission()` (async available).
- Simulator speech is unreliable: multiple Apple Forums reports of `SFSpeechRecognizer` failing in-simulator on iOS 17+/visionOS 2.4, host-mic passthrough breaking across macOS/Xcode combos, and an iOS 18.4 simulator crash on granting the speech permission.
- `AVSpeechSynthesizer` activates the audio session but **does not deactivate it**, leaving other audio ducked; forum reports of the synthesizer breaking once a recognition engine is prepared.

**Assumed / unverified — flag before implementing:**
- Whether **de-DE** is in `SpeechTranscriber.supportedLocales` today. The app ships 20+ localizations (`App/de.lproj` etc.); the user's own utterances are likely en/de-mixed.
- Whether `DictationTranscriber` really accepts `AnalysisContext.contextualStrings` — **single blog source, unconfirmed against Apple docs** (Apple's doc pages are JS-rendered and returned no body to fetch).
- Whether the 1-min / 1000-per-hour limits apply to `requiresOnDeviceRecognition = true` requests, or only to the server path.
- Whether `SpeechTranscriber` needs Apple-Intelligence-class hardware. Sources are silent or contradictory.
- Whether the historical SwiftUI `TextField` + keyboard-dictation bug (only the first character arrives; fixed by wrapping a UIKit field) still reproduces on iOS 26. **This one is load-bearing for Option 0** — test it first.

### The four candidates

| | **0. Keyboard dictation** | **A. `SFSpeechRecognizer`** | **B. `SpeechAnalyzer` + `DictationTranscriber`** | **C. `SpeechAnalyzer` + `SpeechTranscriber`** |
|---|---|---|---|---|
| Code | **Zero** | ~150 LOC + engine | ~200 LOC + asset dance | ~200 LOC + asset dance |
| Info.plist keys | none | mic + speech | mic (+ speech) | mic (+ speech) |
| Audio-session risk | **none** | yes | yes | yes |
| Utterance cap | n/a | 60 s | none | none |
| Device quota | n/a | 1000/hr **device-wide** | none | none |
| **Bias to user's food vocabulary** | **no** | **yes — `contextualStrings`** | reportedly yes (unverified) | **no** |
| Live partials, DOS-styled | no (system chrome) | yes | yes | yes |
| On-device guarantee | not controllable | `requiresOnDeviceRecognition` | on-device | on-device |
| Locale asset handling | OS | OS / Settings | `AssetInventory` | `AssetInventory` |
| Maturity | shipped since forever | 10 years | 1 year | 1 year |

### The honest case for Option 0 (zero code) — read before rejecting it

**The flow the user described already works today.** Open Log Meal → tap the search field → the iOS keyboard raises with a mic key → dictate "200 ml oat milk and a banana" → the text lands in `searchText` → the **ASK AI** row appears at ≥3 chars (`UnifiedFoodEntryView.swift:357`) → tap → staging plate → tap an item → SCAN. Speak-then-scan, zero new code, today.

Option 0 buys: zero permission prompts (system dictation uses its own grant), zero `AVAudioSession` risk near a **glucose alarm** (R1), zero App Review surface, zero simulator problem, zero maintenance.

**Even if you reject Option 0, there is a free win inside it:** nothing in the UI tells the user the keyboard mic works. A one-line hint under the search field is a 10-minute change and is worth shipping regardless of what else is chosen.

**What in-app mic buys over the keyboard, in descending order of weight:**
1. **`contextualStrings` seeded from the user's own food history.** The app knows every food ever logged (`MealEntry`, never pruned) and A1 is making it searchable. Feeding the top ~100 into the recognizer directly attacks the single biggest quality risk — food nouns, brands ("Dextro Energy"), German food words. **The keyboard cannot do this.** This is the strongest argument and it selects a specific API (see D5).
2. Live partial text in DOS amber instead of the system keyboard eating half the screen.
3. One tap instead of two (no keyboard raise, no hunting the mic key on a crowded keyboard mid-hypo).
4. STOP and ASK AI can be the same thumb position (see D3).
5. Enforceable on-device-only (D4). Keyboard dictation's routing is not app-controllable.
6. It is the foundation the hands-free phase needs anyway.

**Recommendation:** build it, but ship the Option 0 hint line in the same PR as the fallback for anyone who denies mic permission.

**Sources:** [Apple QA1951 — Speech Framework API limits](https://developer.apple.com/library/archive/qa/qa1951/_index.html) · [SpeechAnalyzer vs SFSpeechRecognizer](https://blakecrosley.com/blog/speech-framework-vs-sfspeechrecognizer) · [iOS Speech Recognition in 2026](https://picovoice.ai/blog/ios-speech-recognition/) · [iOS 26: SpeechAnalyzer Guide](https://antongubarenko.substack.com/p/ios-26-speechanalyzer-guide) · [WWDC25 — SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/) · [Appcircle WWDC25 write-up](https://appcircle.io/blog/wwdc25-bring-advanced-speech-to-text-capabilities-to-your-app-with-speechanalyzer) · [Apple Forums — AVSpeechSynthesizer doesn't notifyOthersOnDeactivation](https://developer.apple.com/forums/thread/759553) · [Apple Forums — simulator mic broken](https://developer.apple.com/forums/thread/742572) · [Apple Forums — sim crashes on speech permission](https://developer.apple.com/forums/thread/785395) · [Hacking with Swift — SwiftUI dictation into custom fields](https://www.hackingwithswift.com/forums/swiftui/how-to-implement-a-dictation-button-for-custom-input-fields-in-swiftui/27471)

---

## 2. Interaction designs

### Shared state machine

All three options run the same machine. It **ends at READY** and hands off to the already-shipped `foodAnalysisLoading` / staging-plate states. Nothing below is new Redux state — the transcript lives in `@State`, following the follow-up-field precedent (`FoodPhotoAnalysisView.swift:139-143`).

| State | What the user sees | Entered by | Leaves to |
|---|---|---|---|
| `idle` | Mic affordance, amber outline | mount; commit; discard | `permission`, `listening` |
| `permission` | DOS explainer row, then the two system prompts | first mic tap, status `.notDetermined` | `listening` (granted) / `blocked` (denied) |
| `blocked` | "MICROPHONE ACCESS OFF" + `SETTINGS →` row + Option-0 hint | denial, `.restricted`, or locale asset missing | `idle` on return-from-Settings re-check |
| `listening` | Live partial in `amberDark`, blinking block cursor, level meter, `STOP` | mic tap with permission | `finalizing`, `error`, `idle` (cancel) |
| `finalizing` | Partial freezes, `FiguresLoadingView.inline` beside it (<1 s) | STOP tap / auto-stop / interruption | `ready`, `error` |
| `ready` | Final transcript in `amber`, editable, `ASK AI: "…"` armed | final result delivered | existing `analyzeFoodText` flow |
| `error` | `cgaRed` one-liner + `TRY AGAIN` | engine/permission/asset failure | `idle` |

Motion: cursor blink is `AnimationTokens.blink` (that token exists for exactly this — `AnimationTokens.swift:45`). State cross-fades use `AnimationTokens.easeStandard`. **No `ProgressView()` anywhere** — StyleGuard rule 6 fails `Cmd+U` on it under `App/Views`; the level meter is block glyphs or a `Canvas`.

---

### Option A — Mic beside the search field (recommended)

Voice lands exactly where the user's intent already lands, and reuses the shipped ASK AI confirm. No new screen, no new route, no `SheetCoordinator` case.

**Idle**

```
┌────────────────────────────────────────┐
│ LOG MEAL                        [CFG]  │
├────────────────────────────────────────┤
│ ┌────────────────────────────────────┐ │
│ │ Search foods...                    │ │
│ └────────────────────────────────────┘ │
│                                        │
│ QUICK                              >   │
│ [DEXTRO 15g][BANANA 24g][OATS 32g]     │
│                                        │
│ (o) SPEAK                              │  <- NEW
│ []  MANUAL                             │
│ #   SCAN                               │
│ [O] PHOTO                              │
│                                        │
│ RECENT                                 │
│  Porridge with berries           42g   │
│  Flat white                       8g   │
└────────────────────────────────────────┘
```

**Listening** — the SPEAK row expands in place; the list does not navigate.

```
┌────────────────────────────────────────┐
│ ┌────────────────────────────────────┐ │
│ │ Search foods...                    │ │
│ └────────────────────────────────────┘ │
│                                        │
│ ┌ LISTENING ─────────────────────────┐ │
│ │ 200 ml oat milk and a ba_          │ │  <- amberDark = provisional
│ │                                    │ │
│ │ |||..|||||...||..|                 │ │  <- level meter, block glyphs
│ │                        [ STOP ]    │ │
│ └────────────────────────────────────┘ │
│ []  MANUAL   #  SCAN   [O] PHOTO       │  <- still reachable, no nav
└────────────────────────────────────────┘
```

**Ready** — text is now `amber` and editable; the STOP button becomes ASK AI **in the same position**.

```
┌────────────────────────────────────────┐
│ ┌ HEARD ─────────────────────────────┐ │
│ │ 200 ml oat milk and a banana       │ │  <- amber = final, tap to edit
│ │             [ CLEAR ]  [ ASK AI > ]│ │
│ └────────────────────────────────────┘ │
│ #  SCAN INSTEAD    [O] PHOTO INSTEAD   │
└────────────────────────────────────────┘
```

- **Mid-utterance:** provisional words render in `amberDark` with a blinking block cursor; they promote to `amber` as the recognizer finalizes. The user watches it mishear "oat milk" as "oatmeal" *while still talking* — the entire reason to build this instead of shipping Option 0.
- **Correction:** tap the transcript → it is an ordinary editable `TextField` pre-filled with the final string → keyboard for surgical fixes, or `CLEAR` and re-speak. No bespoke correction UI.
- **Barcode/photo mid-flow:** SCAN and PHOTO stay visible throughout. Tapping either auto-stops the mic first (never run `AVCaptureSession` and `AVAudioEngine` concurrently — see R1) and pushes the existing destination. After ASK AI lands on the staging plate, per-item SCAN is already there (`FoodPhotoAnalysisView.swift:462-471`).

**The `.searchable` constraint — a real finding.** The search field is `.searchable(text:prompt:)` (`UnifiedFoodEntryView.swift:90`), and SwiftUI exposes **no API for a trailing accessory view inside the system search field**. Putting a mic *inside* the search bar therefore means either replacing `.searchable` with a bespoke DOS field (a large diff that collides head-on with the in-flight A1 work) or introspection hacks (not house style). **Hence the SPEAK row rather than an in-field icon** — smallest diff, survives A1, honest about the platform. Verify the constraint at implementation time; if iOS 26 has added an accessory API, the in-field variant is strictly nicer.

---

### Option B — VOICE console (a dedicated screen)

The one that matches the vision's ambition. Pushed onto the existing `NavigationStack`, so no nested-sheet violation.

```
┌────────────────────────────────────────┐
│ < CANCEL           SAY IT              │
├────────────────────────────────────────┤
│                                        │
│  ┌──────────────────────────────────┐  │
│  │                                  │  │
│  │  200 ML OAT MILK AND A           │  │
│  │  BANANA_                         │  │
│  │                                  │  │
│  └──────────────────────────────────┘  │
│                                        │
│      ..|||||||||||||||||..             │
│      LISTENING            0:04         │
│                                        │
│  ┌────────┐ ┌────────┐ ┌────────┐      │
│  │  STOP  │ │  SCAN  │ │ PHOTO  │      │
│  └────────┘ └────────┘ └────────┘      │
│                                        │
│  [           ASK AI  >           ]     │
└────────────────────────────────────────┘
```

- Big target, glanceable, mid-hypo-friendly, one-handed.
- Elapsed timer makes the 60 s ceiling (if D5 = `SFSpeechRecognizer`) legible instead of mysterious.
- **Cost:** a new screen, a new route, and SCAN/PHOTO duplicated one navigation level up from where they already live. Two ways to reach the same destination is the kind of drift that made `SheetCoordinator` necessary.
- **Verdict:** this is the right *destination*, wrong *phase*. It becomes the hands-free session screen in the next phase, when the app also speaks back. Building it now means building it twice.

---

### Option C — Mic on the staging plate only (correction side-car)

Add the mic solely to the CLARIFY follow-up field (`FoodPhotoAnalysisView.swift:604-639`).

```
┌────────────────────────────────────────┐
│ CANCEL          AI MEAL ANALYSIS       │
├────────────────────────────────────────┤
│ NUTRITION                              │
│  62g C                  from 3 items   │
│ FOOD ITEMS - tap to edit               │
│  > Oat milk                     18g    │
│  > Banana                       24g    │
│ CLARIFY                                │
│  Can you be more specific?             │
│  ┌──────────────────────────┐ ┌──────┐ │
│  │ it was a big bowl_       │ │ (o)  │ │
│  └──────────────────────────┘ └──────┘ │
│                          [ SEND ]      │
└────────────────────────────────────────┘
```

- Directly implements the vision doc's "Voice Side-Car Logging": AI misses something after a photo, user says it.
- Tiny diff, low risk, no new navigation.
- **But it does not satisfy the intent contract** — the user asked to *start* with voice, not to correct with it.
- **Verdict:** not a standalone V1, but it is a ~20-line add-on once the control from Option A exists. Ship both in one PR.

---

### Comparison

| | A (row + inline panel) | B (console) | C (staging plate) |
|---|---|---|---|
| Satisfies intent contract | **yes** | yes | no |
| New screen / route | no | yes | no |
| Collides with A1 worker | low (one new row) | none | none |
| Duplicates existing affordances | no | yes (SCAN/PHOTO) | no |
| Path to hands-free phase | needs the console later | **is** the console | no |
| Estimated size | S–M | M–L | XS |
| **Verdict** | **V1** | defer to hands-free phase | **bundle with A** |

---

## 3. Decisions

Six either/ors. Recommendations are mine; the reasoning is what matters.

### D1 — Commit semantics: auto-stop on silence **vs** explicit tap-to-stop

**Recommend: explicit tap-to-stop, with silence auto-stop only as a safety net.**

Concretely: STOP is the commit. Additionally, ≥15 s of continuous silence *or* the engine ceiling (55 s if D5 = `SFSpeechRecognizer`) stops the mic — but stopping is **not** dispatching (see D3), so a spurious auto-stop costs nothing.

Why: the user's own phrasing has pauses — *"I'm eating this… uh… about 200 mL of…"*. A 1.5 s endpoint detector truncates that mid-thought, and truncation is the failure mode people abandon voice over. But leaving the mic open indefinitely is a battery and privacy problem, especially with `UIBackgroundModes: audio` already declared (R1/R5).

The counter-argument, stated fairly: tap-to-stop is one extra interaction, and mid-hypo one-handed that matters. Mitigated by making STOP a large target that then *becomes* ASK AI in place.

### D2 — Live partial transcript **vs** final text only

**Recommend: show partials, visually distinct.** Provisional words in `AmberTheme.amberDark` with a blinking block cursor (`AnimationTokens.blink`); promoted to `AmberTheme.amber` on finalization.

Why: watching the recognizer mishear a food name while you can still restate it is the primary UX advantage over Option 0. Costs one flag (`shouldReportPartialResults = true` / `.volatileResults`) and one colour branch. The DOS aesthetic gives the dim/bright distinction for free — no new tokens.

Only reason to say no: partial flicker reads as instability. If that bothers you on device, the fallback is partials-with-a-100 ms-settle rather than final-only.

### D3 — Auto-dispatch to the AI **vs** explicit confirm

**Recommend: explicit confirm.** Committing puts the transcript in the field and *arms* ASK AI. It does not fire.

Why:
1. **Every dispatch is a paid Claude Haiku call on the user's own API key.** Voice lowers friction; auto-dispatch turns every stray tap into spend.
2. STT errors on food nouns are the expected case, not the exception. Auto-dispatch makes correction cost a full network round-trip instead of a keystroke.
3. It keeps spoken and typed input **identical downstream** — same `Button`, same guard at `UnifiedFoodEntryView.swift:380`, same consent behaviour. Two dispatch paths means two bug surfaces.
4. `.analyzeFoodText` is consent-gated by `aiConsentFoodPhoto`; auto-firing pre-consent silently no-ops in `ClaudeMiddleware.swift:42` and would strand `foodAnalysisLoading`. The existing view already guards this correctly — inherit it, don't re-derive it.

The counter: one extra tap on the happy path. Mitigation: STOP and ASK AI occupy the **same screen position**, so it is the same thumb landing twice, not a hunt.

### D4 — On-device only **vs** server fallback

**Recommend: on-device only in V1.** Set `requiresOnDeviceRecognition = true` (or use the new API, which is on-device by construction). At mount, check `supportsOnDeviceRecognition` / `installedLocales`; if unavailable for the locale, **hide the mic and show the Option-0 keyboard hint** rather than silently routing audio to Apple's servers.

Why: `docs/development-rules.md` mandates offline-first and privacy-by-design. The app gates *text* to Claude behind an explicit consent screen; silently streaming raw microphone audio to a different vendor's servers with no consent surface is an inconsistency the user would have to explain to himself. Also, the server path burns the device-wide 1000-req/hour quota shared with every other app.

The counter, stated fairly: server recognition is more accurate, and on-device de-DE assets may be absent. If device testing shows on-device German is genuinely unusable, revisit — but as an explicit Settings toggle with its own copy, not a silent fallback.

### D5 — Which engine: `SFSpeechRecognizer` **vs** `SpeechAnalyzer`

**Recommend: `SFSpeechRecognizer` for V1, behind a one-protocol seam.** This is the closest call in the doc.

For `SFSpeechRecognizer`:
- **`contextualStrings` is the single highest-leverage quality lever available**, and it is verified. Seed ~100 phrases from `favoriteFoodValues` + `recentMealEntries` and the recognizer is biased toward *this user's actual foods*. `SpeechTranscriber` explicitly does not accept contextual strings; `DictationTranscriber` reportedly does, but that is one unverified blog source.
- The 60 s / 1000-per-hour limits **do not bind** at "one 8-second utterance per meal."
- Materially less code. No `AssetInventory` allocation/deallocation dance, no "the OS deleted your model under disk pressure" state.
- Not deprecated. 10 years of Stack Overflow behind it.

For `SpeechAnalyzer`:
- Where Apple is going; `SFSpeechRecognizer` will presumably be deprecated eventually.
- No caps, better long-form model, `isFinal` semantics that are cleaner than the callback API.

**Tripwires that flip this:** (a) de-DE contextual biasing measurably fails to help on device; (b) Apple deprecates `SFSpeechRecognizer` in the iOS 27 betas; (c) `DictationTranscriber`'s `contextualStrings` is confirmed real in the SDK — then go new-API immediately, since it dominates on every other axis.

**De-risk either way:** put the engine behind a small `protocol SpeechEngine { func start(contextualStrings:) -> AsyncStream<Transcript> ; func stop() }`. The sink is a `String`; swapping engines is then one file. Note this is **not** an `if #available` guard — CLAUDE.md's DMNC-776/777/778 sweep removed those and none should return.

### D6 — Which interaction option

**Recommend: A + C in one PR. Defer B.** Rationale in §2's comparison table.

---

## 4. Risk register

### R1 — `AVAudioSession` coexistence (highest severity: this one is a safety risk)

Today's state: `DirectNotifications.playSound` sets `.playback` + `.mixWithOthers` and `setActive(true)` at `Library/DirectNotifications.swift:163-164` and **never deactivates**. `ReadAloud`'s `AVSpeechSynthesizer` activates implicitly and, per Apple Forums, also never deactivates — leaving other audio ducked. So the session may already be active in `.playback` when the mic is tapped, and recording under `.playback` fails.

**The safety consequence, stated plainly: a low-glucose alarm can fire while the mic is open.** If the dictation session change makes `playSound` inaudible, that is a safety regression, not a cosmetic one.

Ownership rules for the implementation:
- The dictation service is the **only** code that calls `setActive(false)`, and only for a session **it** activated. It must never deactivate on ReadAloud's behalf.
- Use `.playAndRecord` with `.mixWithOthers` (**not** `.duckOthers`) + `.defaultToSpeaker`, so `playSound`'s own `setCategory(.playback, .mixWithOthers)` can still take effect mid-dictation.
- On stop: `setActive(false, options: .notifyOthersOnDeactivation)` — that option is meaningful *only* when the first argument is `false`.
- Observe `AVAudioSession.interruptionNotification` and end dictation gracefully (→ `finalizing`, keep whatever was heard).
- Stop the engine on `scenePhase != .active`. With `UIBackgroundModes: audio` already declared, a leaked record session is an app that is genuinely listening in the background.
- Hard-cap mic-open duration regardless of D1.

**Mandatory device test:** start dictating → force a low alarm → confirm the alarm is audible at the configured volume. This is a release gate, not a nice-to-have.

### R2 — Permissions

Two prompts (`NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`), both absent from `Info.plist` today, and **the app hard-crashes if either is missing**. Fire them lazily on first mic tap — mic first, then speech — behind a single DOS explainer row, never at launch.

Denial path: `BarcodeScannerView.swift:245-258` handles camera denial with `default: break` — **do not copy that**; it silently does nothing. Show the `blocked` state with a `SETTINGS →` row (`UIApplication.openSettingsURLString`, App-only) plus the Option-0 keyboard hint as a working alternative. iOS never re-prompts after denial. Treat `.restricted` (MDM / Screen Time) as permanently blocked, not retryable. Re-check status on return from Settings via `scenePhase`.

### R3 — Recognition quality for food vocabulary and units

- **Mitigation:** seed `contextualStrings` from `favoriteFoodValues` + `recentMealEntries` (dedupe, cap at the ~100-phrase limit, recency-ordered). This is D5's whole argument.
- **Units need no work.** `ClaudeService.swift:220-232` already normalizes both "200ml" and "a cup". Whether the recognizer emits "100 mL", "100ml", or "one hundred mils", the LLM resolves it. Do not write a unit parser.
- Set `addsPunctuation = false` in V1 — punctuation buys nothing here and can insert spurious sentence breaks. Flag as tunable.
- Locale: `Locale.current` in V1. A user-facing locale picker is deferred (§6). The user is likely en/de-mixed; this is the thing to watch first on device.

### R4 — The simulator cannot do real speech-to-text

Verified: host-mic passthrough is historically broken across macOS/Xcode combinations, `SFSpeechRecognizer` has repeated in-simulator failure reports on iOS 17+, and one simulator build crashes on granting the speech permission. **Assume it does not work and design testing so it does not matter.**

Five-layer strategy:

1. **Push all branching into a pure model.** Extract `DictationDisplayModel` mapping `(authorizationStatus, engineAvailable, partialText, finalText, error) → (visibleState, buttonEnabled, transcriptColorRole, message)`. Precedents to copy: `GlucoseStatusBarModel` (`GlucoseStatusBar.swift:25-72`) and `HypoFilteredEntryModel` (`UnifiedFoodEntryView.swift:13-25`). Test with Swift Testing. **This is where the bugs live, and it needs no audio.**
2. **`#if targetEnvironment(simulator)` fallback, mirroring `BarcodeScannerView.swift:152-186` exactly.** The mic control renders "SPEECH UNAVAILABLE IN SIMULATOR" plus a text field wired to the *same* `onTranscript(String)` callback and the same commit path. This exercises the entire downstream flow — commit → ASK AI → staging plate → SCAN — under `xcodebuild test`. House precedent exists; it is not a bespoke hack.
3. **Optional canned-audio path (DEBUG only, excluded from Release):** `SFSpeechURLRecognitionRequest` against a bundled short `.wav` proves engine wiring without a live mic.
4. **Device checklist** — the only place these can be answered: real de-DE/en quality on ~10 utterances the user actually says; **alarm-during-dictation audibility (R1)**; denial → Settings → return; AirPods vs speaker vs CarPlay; incoming call interruption; screen lock mid-utterance; backgrounding mid-utterance.
5. **Do not gate the PR on simulator STT.** The user dogfoods daily on device; he is the acceptance tester for the engine layer.

### R5 — App Review and privacy

Microphone + `UIBackgroundModes: audio` in the same binary invites scrutiny. Write specific usage strings, e.g.:

> "DOSBTS uses the microphone only while you are dictating a meal. Speech is transcribed on your device and is not recorded or uploaded."

Privacy-by-design rule (`docs/development-rules.md`): **never log the transcript** via `DirectLog`. `.analyzeFoodText(query:)` already carries the text through Redux and that is fine and pre-existing — but nothing new should widen that surface.

### R6 — Consent-gate interaction

`.analyzeFoodText` is gated on `aiConsentFoodPhoto`; the barcode path is not. Pre-consent the mic should still work (it fills a **search** field, which is useful on its own) but must never dispatch — which D3's explicit confirm gives for free, since the ASK AI row already lives inside `if store.state.claudeAPIKeyValid || store.state.aiConsentFoodPhoto` (`UnifiedFoodEntryView.swift:342`).

### R7 — Cost

Each ASK AI is a paid Haiku call on the user's own key. Voice → more calls. D3 is the control. Follow-ups are already capped at 3 rounds / 4000 chars (`FoodPhotoAnalysisView.swift:624-628`).

### R8 — Merge collision with DMNC-1484-A1

A sibling worker is adding DB-backed history search to this exact view right now, and its plan explicitly says *"voice… will add a mic to this same search field later, so keep this change surgical."* Reciprocate: voice adds **one new row** to `actionsSection` plus `@State` for the transcript. It must not touch `filteredRecents`, `recentsSection`, the debounce, or `MealItemRow`. Rebase onto A1 before opening the PR.

### R9 — Style guards and project mechanics

`StyleGuardTests` reads `.swift` off disk: no `.font(.system(`, no `.foregroundColor`, no `Color.black`, no `cornerRadius`, no `ProgressView()` under `App/Views`, no inline animation curves, no raw `Color(red:)` outside `AmberTheme`, and any `header: {` needs `.dosHeader(` within 8 lines. New `.swift` files under `App/` auto-sync via `fileSystemSynchronized` — **but new test files need four manual `project.pbxproj` edits**. A1's plan claims the next free id pair; if A1 landed, take the *next* pair and re-check, do not reuse. Finish with `plutil -lint`.

---

## 5. Recommended V1 slice — worker brief

**Decision assumed:** A + C, `SFSpeechRecognizer`, tap-to-stop, live partials, explicit confirm, on-device only. **Size: S–M, one PR, one focused day.** (The roadmap's "L" priced the full vision; this slice is smaller because units and the scan-mid-flow leg already ship.)

**In scope**

1. `App/Info.plist` — add `NSMicrophoneUsageDescription` + `NSSpeechRecognitionUsageDescription` with the R5 copy.
2. `App/Modules/Voice/SpeechService.swift` (new) — `AVAudioEngine` + `SFSpeechAudioBufferRecognitionRequest`, `requiresOnDeviceRecognition = true`, partials on, `contextualStrings` injected by the caller, R1's session ownership rules, interruption + scene-phase teardown. Deliberately **not** a middleware and **not** in Redux — it sits in `Modules/Voice/` alongside `Modules/Claude/`'s `ClaudeService`/`KeychainService` precedent. Behind a `SpeechEngine` protocol (D5 seam).
3. `App/Views/SharedViews/DictationControl.swift` (new) — the reusable control: idle/listening/finalizing/ready/blocked/error rendering, `onTranscript: (String) -> Void`, DOS styling, `AnimationTokens.blink` cursor, block-glyph level meter, `#if targetEnvironment(simulator)` text-field fallback per R4.2.
4. `App/Views/SharedViews/DictationDisplayModel.swift` (new) — the pure model per R4.1.
5. `App/Views/AddViews/UnifiedFoodEntryView.swift` — one `SPEAK` row in `actionsSection`; transcript → `searchText`; contextual strings from favourites + recents. Surgical (R8).
6. `App/Views/AddViews/FoodPhotoAnalysisView.swift` — mic beside the CLARIFY field, transcript → `followUpText` (Option C).
7. Option-0 hint line in the `blocked` state.
8. `DOSBTSTests/DictationDisplayModelTests.swift` (new, + four pbxproj edits) — every row of the §2 state table.
9. `CHANGELOG.md` `[Unreleased]`.
10. `docs/references/food-logging-2026-vision.md` **lines 17 and 79** — replace Wispr with in-app mic / DMNC-1486.

**Explicitly not in scope:** `App/App.swift` (neither middleware array changes — there is no middleware), `SheetCoordinator` (no new sheet), any Redux state or action, `ClaudeService`, `DirectState`/`DirectReducer`/`AppState`/`UserDefaults`.

**Acceptance criteria**

- [ ] Tap SPEAK in Log Meal → prompts appear once → dictate → partial text visible **while speaking**, dim, blinking cursor.
- [ ] STOP → text finalizes to bright amber in the search field; **nothing dispatches**.
- [ ] `ASK AI: "…"` appears in the same position STOP occupied; tapping it runs the existing flow unchanged.
- [ ] Tap the transcript → editable; CLEAR resets to idle.
- [ ] SCAN / PHOTO reachable while listening; tapping either stops the mic first, then pushes.
- [ ] Deny mic → `blocked` state with `SETTINGS →` and the keyboard-mic hint; returning from Settings re-checks.
- [ ] Airplane mode → dictation still works (on-device proof).
- [ ] **Alarm audible while the mic is open** (R1 release gate).
- [ ] Backgrounding mid-utterance stops the engine.
- [ ] Simulator: fallback text field drives the same commit path; `xcodebuild test` green; StyleGuard green.
- [ ] Staging plate CLARIFY mic dictates into the follow-up field and SEND behaves as today.

---

## 6. Explicitly deferred

| # | Item | Why not now |
|---|---|---|
| D-1 | **Hands-free spoken dialog** (app speaks back, no touching) | The real vision. Needs full-duplex arbitration with `ReadAloud`, barge-in, and an audio-session owner that also owns alarm playback. A phase, not a feature. |
| D-2 | **Siri / App Intents** (`AddMealIntent`) | Bypasses Redux **and** the AI path; a separate architecture decision about what a meal logged outside the app even means. |
| D-3 | **Voice + photo fusion in one request** | The vision doc's "side-car". Highest user desire of anything deferred. Needs a new `ClaudeService.analyzeFood(imageData:note:)` and a prompt change — `analyzeFood` takes no text today (`ClaudeService.swift:25`). Worth its own issue now. |
| D-4 | **Dictated journal notes** (DMNC-1485) | Reuses `DictationControl` in ~5 lines once it exists. Kept out to keep this PR single-purpose. |
| D-5 | **Personal portion presets** ("my mug = 300 mL", "chunks") | This is DMNC-1484-A2, extending `Library/Content/ServingPreset.swift`. Explicitly **not** a dependency — the generic unit resolution already ships. |
| D-6 | **Server-fallback recognition + Settings locale picker** | Revisit only if on-device de-DE quality actually bites (D4). |
| D-7 | **`SpeechAnalyzer` migration** | Behind the `SpeechEngine` seam. Triggered by D5's tripwires. |
| D-8 | **Wake word / always-listening** | No. |
| D-9 | **Voice for insulin / BG entry** | Dosing-adjacent. Needs its own safety argument. |
