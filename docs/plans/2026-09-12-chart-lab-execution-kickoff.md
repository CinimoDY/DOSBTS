# Chart Lab — execution kickoff (build all seven, ship one TestFlight build)

**Date:** 2026-09-12 · **Base:** `main` (planning verified at `3a288d3d`; re-verify anchors on the tree you branch from) · **Tracking:** DMNC-1500 umbrella; P0 = DMNC-1504, P1 = DMNC-1506, P2 = DMNC-1501 (re-scoped), P3 + P4 = DMNC-1503 (re-scoped), P5 = DMNC-1505; DMNC-1502 (COB) deferred · **Controller:** Fable, fresh session, in `/Users/doke/extracode/DOSBTS` on `main`.

**Dom's decision (verbatim, 2026-09-12):** "they all look interesting. can we just build all and deploy to testflight? that way i can play about, test on device and then give feedback"

## What exists — read these, do not re-explore

| Artifact | Path | Use it for |
|---|---|---|
| Chart-layer map | `docs/plans/2026-09-11-chart-lab-exploration-dossier.md` | every `file:line` anchor in the chart layer, marker-lane invariants, load windows, design-system rules |
| Planning brief | `docs/plans/2026-09-11-chart-lab-fable-kickoff.md` | constraints every worker brief must inline (§"Constraints"), orchestration recipe (§"Orchestration") |
| Ideation (7 ranked ideas + rejections) | `docs/ideation/2026-09-12-chart-lab-ideation.html` | the WHAT of each surface: description, basis, downsides. Ideas 1–7 map to P0–P5 below |
| Prototype canvas (8 artboards) | Artifact "DOSBTS Chart Lab" — https://claude.ai/code/artifact/0f40d578-b3a3-460c-a651-aff0f3240dfb · sources `.context/compound-engineering/ce-prototype/2026-09-12-chart-lab-directions/` (gitignored; regenerate with `node generator/build.mjs 01-chart-lab-directions/screens`) | the LOOK of each surface — the artboard is the visual spec; copy its states, labels and legends |
| Decisions capsule | `.context/compound-engineering/ce-prototype/2026-09-12-chart-lab-directions/decisions.md` | what was decided, deferred, still open |
| Orchestration best practice | `docs/solutions/best-practices/plan-driven-parallel-worker-orchestration.md` | plan → dispatch → review → merge train → integrate |
| P0 worker plan (ready) | `docs/plans/2026-09-12-chart-lab-p0-lab-shell-plan.md` | dispatch first, alone |

Decisions already taken (do not re-litigate): native `LabChartView` (shipping `ChartView` body gets only switch arms); marker lane hidden on lab tabs; everything behind `showChartLab` (off by default); the AI never receives readings; no dosing language anywhere; every derived number ships with its N; offline-first rendering.

## The cut

P0 lands **first, alone** (it owns the plumbing every other PR needs). P1–P5 branch from the merged `main` and run **in parallel**. Then the merge train, one full-suite run on `main`, the build bump, and `./deploy.sh`.

| PR | Surface | Ideation idea | Tier | Sim UDID (target by `id=`) | pbxproj test-file IDs (fileRef / buildFile) | Linear |
|---|---|---|---|---|---|---|
| **P0** | Lab shell: `showChartLab`, four `ReportType` lab cases + scrollable row, `LabChartView` with parity marks, **instrument cursors** (sticky scrub, A/B range, fixed readout strip, detached FOLLOW + `◂ N NEW`, detent haptics), `LabChartInputs/Series` builder, `ChartLabOverlay` seam with empty arms, placeholders for NIGHT/SWEEP/PATTERNS, Settings toggle | 1 | Opus | iPhone 17 Pro 26.5 `9A948885-80C7-4A96-A9FB-D2742595AD3B` | `C1AB15010000000100A00001` / `…00002` | DMNC-1504 |
| **P1** | `LAB: NIGHT` + whole-system window: `.loadLabWindow(interval, streams)` middleware (one action, per-stream `.catch`, coverage per stream), `LabStream` registry, continuous 20:00→10:00 window across midnight, HealthKit **sleep** read (new read type on the existing authorisation) + stage lane, HR line, POST coverage strip, the dinner ribbon/IOB tail carried across midnight | 2 | Opus | iPhone 17 Pro Max 26.5 `0272B8A9-4EA4-4E13-A584-3A7E0262CBE2` | `C1AB15040000000100A00001` / `…00002` | DMNC-1506 |
| **P2** | `LAB: MEALS` overlays: `ResponseWindow` kernel (anchor-agnostic, `n` + `isLowConfidence` + confounders), carb-sized dots on the curve, graded live ribbon that hardens and names its confounder (Ratio Lab exclusion tags, `60g ⟷ 5U` bracket), **residual** `?` marks with the prefilled backdated journal-note sheet, **regime** bands from tags (derived, never stored; per-tag default durations; `STILL STRESSED? Y/N` row) | 3 + 6 | Opus | iPhone 17 26.5 `653F1D37-862C-4829-A384-C4403636B338` | `C1AB15010000000200A00001` / `…00002` | DMNC-1501 (re-scoped) |
| **P3** | `LAB: SWEEP`: event-locked overlay — new multi-day read "glucose ±4 h around every meal in 7/30/90 d" on the clinic-report path (one `asyncRead`, no writes), relative-minutes numeric x-axis (its own `Chart`), sweeps tiered by age, p25–p75 per 5-min bin, median, carb-bucket chips, CLEAN ONLY, `TODAY +47` trace, LAPS row (3–5 twins by carb bucket ±25 % and time ±90 min) | 4 | Opus | iPhone 17 Pro 26.4 `60D83334-1820-41BC-8056-5D921FD8296B` | `C1AB15030000000100A00001` / `…00002` | DMNC-1503 (P3 half) |
| **P4** | `LAB: PATTERNS`: `hourlyPatterns` extended with p5/p95 (pin in `ClinicReportTests`), 30-day band loaded via `ClinicReportStore.getClinicReportData(days:)`, ghost band under today on the lab chart, out-of-band ticks + `+38 VS USUAL · n=27` card, `PATTERN HOUR` tag, hold-to-drill `SAME HOUR · 14 D` overlay, 7d/30d/90d chips | 5 | Opus (seam) — views Sonnet-able | iPhone 17 Pro Max 26.4 `F4D018BE-52B6-409E-AF86-C07A1710831F` | `C1AB15030000000200A00001` / `…00002` | DMNC-1503 (P4 half) |
| **P5** | Cited facts (offline only): `hypoEpisodes` → `[DateInterval]` refactor, `ChartHighlights` detectors → id-carrying `LabFigure`s (N required by type), feature sheet line, numbered pins on the lab chart, staged-reveal cards incl. the Black Box hypo card, `AXChartDescriptor` summary. **No NARRATE button in this build** (wave 5) | 7 | Opus | iPhone 17 26.4 `ACB4E809-739A-47D4-AF24-EF51BAB88214` | `C1AB15050000000100A00001` / `…00002` | DMNC-1505 |

Deferred from this build: DMNC-1502 COB model + model-vs-observed ribbon; wave 5 NARRATE + chart builder (`LAB: MINE`); HealthKit steps; Radar Loop; Teletype Week.

### Shared-file conflict profile (merge-train order: P5 → P4 → P3 → P1 → P2)

All five parallel PRs touch `CHANGELOG.md` (keep-both; only P0's toggle line is user-visible — lab surfaces are gated, so P1–P5 add **no** changelog entries unless a shipping surface changes), `project.pbxproj` (distinct ID pairs above; `plutil -lint` + the `-list | grep -i "malformed\|multiple groups"` check after every merge), and `App/Views/Overview/Lab/LabOverlayMarks.swift` (one `switch` — each PR fills its own arm; build the combined branch before each merge). P1 and P2 both read `journalNoteValues`; P2 and P5 both touch `MealOverlayLogic.swift` (P2 generalises `computeMealOverlayDelta` into the kernel; P5 only reads it) — merge P5 before P2.

## Worker brief skeleton (inline in every dispatch)

1. Plan path + "execute faithfully; read before editing; record deviations in `IMPLEMENTATION_NOTES.md`; never claim success without command output; commit, push, open the PR; fold notes into the PR body and `git rm` the file before the train".
2. Worktree + branch off `main`; sim UDID; the sibling-conflict clause ("base only on `main`; never rebase onto or merge sibling work").
3. The kickoff's constraint list verbatim (StyleGuard rules, no glow in `Chart{}`, explicit scale domains, tests UserDefaults-isolated, Redux 4-file lockstep, `makeTestDefaults()`), plus: the artboard for this surface is the visual spec; every derived number ships with its N; no dosing language; the lab is off by default.
4. Verification: `xcodebuild test … > "$LOG" 2>&1; grep "TEST SUCCEEDED"` — never pipe into `tail`; known-flaky `AppGroupMiddlewareDispatchTests/startupSeedsKeys()`.

## Review, train, integrate, ship

- One adversarial reviewer per PR (`swift-reviewer` + `redux-state-coherence-reviewer` where state changes); findings back to the **same** worker.
- Merge most-isolated-first (order above); expect "Base branch was modified" — poll, don't hammer.
- Full suite once on merged `main`. Then the deploy tail per CLAUDE.md: verify something user-visible landed (the toggle line), bump `CURRENT_PROJECT_VERSION` (4 places) to `max(local, TestFlight latest) + 1`, promote `[Unreleased]` → `[Build N]`, `./deploy.sh` (it copies the changelog first; check the previous TestFlight upload is > 30 min old; `ASC_APP_ID` must be set for the notes push), then commit `chore: sync bundled changelog for Build N`.
- After upload: comment the build number on DMNC-1500 and tell Dom the toggle lives in Settings → Glucose & Display → Chart Lab.

## Paste-in brief for the fresh controller session

> Execute the DOSBTS Chart Lab per `docs/plans/2026-09-12-chart-lab-execution-kickoff.md`. Read that file, then the P0 plan it names, then `docs/ideation/2026-09-12-chart-lab-ideation.html` and the dossier. Write worker-executable plans for P1–P5 under `docs/plans/` (same standard as the P0 plan: verified `file:line` anchors, exact interfaces, test-first steps, named suites, a simulator script, the ID pair and UDID from the kickoff table, an explicit out-of-scope line), dispatch P0 first and alone, then fan out P1–P5, review, merge-train, run the full suite on `main`, bump and deploy to TestFlight. Do not orchestrate from a weak model.
