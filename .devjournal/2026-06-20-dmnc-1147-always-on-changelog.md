# DMNC-1147: Always-On Changelog — in-app What's New + TestFlight release notes

**Date:** 2026-06-20
**Branch:** claude/dmnc-1147
**PR:** _pending_

## What changed

Drives a user-facing changelog from the existing `CHANGELOG.md` (single authored source) across two surfaces — an in-app "What's New" and TestFlight release notes — with no per-build authoring. Built from `docs/plans/2026-06-20-001-feat-always-on-changelog-plan.md` (7 units).

### U1 — Changelog parser (`Library/Content/Changelog.swift`)

Pure `ChangelogParser.parse(_:) -> [ChangelogBuild]` (newest-first, `[Unreleased]` excluded). Models: `ChangelogBuild` (numeric `buildNumber` for sort/dedup/id + `displayName` preserving range labels like `35–48`), `ChangelogSection` (Added/Changed/Fixed/Removed), `ChangelogEntry` (cleaned text + optional `destinationKey`). Cleaning reproduces the KTD2 grammar: **iterative** trailing-metadata strip (handles chained `— A — B` runs, multi-issue, `follow-up`/`wave` trailing words, trailing periods) that never eats an embedded prose em-dash; `{tour:<key>}` marker extraction. Lenient like `DigestInsight.parse` — malformed input degrades, never crashes. `ChangelogParserTests` (13 tests) pins it against the real corpus shapes.

### U2 — Bundled resource (`Library/Resources/CHANGELOG.md`)

`ChangelogParser.bundled()` reads the committed copy via `FrameworkBundle.main`. Added the resource to the widget's `PBXFileSystemSynchronizedBuildFileExceptionSet` (excluded from the widget). **Verified `.md` actually bundles** into `DOSBTSApp.app` and is absent from the widget appex.

### U3 — Last-seen-build state + present decision

`lastSeenBuild: Int` via the 5-touch UserDefaults pattern (`integer(forKey:)` → `0` fresh-install sentinel). Pure `WhatsNewPresenter.shouldPresent(currentBuild:lastSeenBuild:alarmActive:)` + `buildsToShow(builds:since:cap:)` (newest-first, capped slice + full set). `WhatsNewPresenterTests` covers AE1/AE2/AE3 + the reducer.

### U4 — Deep-link destinations + Settings-category nav

`ChangelogDestination` (closed key set → tab tag or `(settings, category?)`) with `actions() -> [DirectAction]`. New transient (non-persisted) `selectedSettingsCategory` state + `navigationDestination(item:)` in `SettingsView` (coexists with the existing closure NavigationLinks). `ChangelogDestinationTests` table-tests the closed set + reducer.

### U5 — Patch-notes renderer (`App/Views/WhatsNew/WhatsNewView.swift`)

DOS patch-notes cards: `PATCH NOTES · BUILD N` banner, CGA-coded section labels (green/amber/cyan/red), the digest's staged reveal (lifted `stagedReveal` from `DigestView` into shared `DOSModifiers.swift`), `.id(buildNumber)` re-arm, `SHOW ALL N BUILDS` expansion. Permanent history entry in Settings → System & About (`AboutView`). Empty state `NO CHANGELOG DATA`.

### U6 — Auto-present wiring

`ContentView.presentWhatsNewIfNeeded()` (onAppear + `onChange(of: appState)`): guard-unwraps `Int(DirectConfig.appBuild)`, composes the alarm predicate (`treatmentCycleActive || showTreatmentPrompt || recheckDispatched`), advances `lastSeenBuild` **at present time** (KTD5), records silently on fresh install. Checked **before** `presentTreatmentSheetIfNeeded()` so the alarm predicate reads the treatment flags before they're cleared. New `SheetCoordinator.whatsNew(builds:allBuilds:)` (constant id) routed through `RootSheetContent` in its own `NavigationStack` + Done button; deep-link taps dismiss-then-navigate (no nested sheet).

### U7 — Deploy automation (`deploy.sh`, `scripts/asc-release-notes.sh`, `scripts/asc-jwt.py`)

`deploy.sh` runs `cp CHANGELOG.md Library/Resources/CHANGELOG.md` **before archiving** (so the bundle carries the shipped changelog), then `asc-release-notes.sh` fail-soft after upload. The notes script extracts the latest `[Build N]` block, cleans it with a perl regex that **reproduces the Swift parser's grammar** (verified byte-identical to `ChangelogParser`'s output for build 106), opens `$EDITOR` with a FOCUS/KNOWN-ISSUES scaffold, polls `GET /v1/builds`, and PATCH/POSTs `betaBuildLocalizations.whatsToTest`. Credentials come from env vars (`ASC_*`); changelog text never touches a shell command line (env-var → file → python JSON-encode → curl stdin). `asc-jwt.py` mints the ES256 JWT via `openssl` + a DER→raw R‖S conversion — **verified end-to-end** (the signature validates against the public key via openssl).

## Why

`CHANGELOG.md` is maintained with discipline but stopped at the repo; TestFlight's "What to Test" was left empty (hand-authoring was tried and abandoned for builds 61/62). This derives both user-facing surfaces from the one source, so there's no recurring chore. The in-app surface doubles as feature discovery for a dense app.

## Review fixes applied

- **VoiceOver:** the card collapses children (`children: .ignore`), so the per-entry deep-link `onTapGesture` was unreachable to VoiceOver — added `.accessibilityActions { … }` exposing each linked entry as a custom action.
- **Verbatim rendering:** switched entry text from `LocalizedStringKey` to `Text(verbatim:)` — honors R9 and removes the latent risk of a future `[label](url)` entry rendering as a live link that bypasses the closed-set destinations.
- **JWT empty-Bearer:** `Bearer $(mint_jwt)` in argument position doesn't abort on a mid-run signing failure under `set -e` — mint into a local var first in `asc_get`/`write_notes`.
- **Char count:** `wc -c` (bytes) → perl char count for the 4000-char ASC limit (the cleaned text is em-dash/bullet heavy).
- **DER robustness:** `der_to_raw` now surfaces truncated/malformed signatures as a clean exit, not a traceback.

Redux state lockstep reviewed clean (both `lastSeenBuild` persisted and `selectedSettingsCategory` transient). Accepted per plan: the additive `navigationDestination` + closure-NavigationLink coexistence (KTD6, manual-verify mitigation), the KTD7 alarm predicate, and the once-per-update main-thread `bundled()` parse.

## Tests

`ChangelogParserTests`, `WhatsNewPresenterTests`, `ChangelogDestinationTests` pass; full suite green (no regressions). App + widget build clean. Shell verified via `bash -n`, a parser-vs-perl cross-check, and an openssl JWT signature round-trip.
