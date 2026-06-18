---
title: "feat: Prototype-Driven Design Workflow (DOSBTS-side)"
type: feat
date: 2026-06-18
origin: docs/brainstorms/2026-06-18-prototype-driven-design-workflow-requirements.md
---

# feat: Prototype-Driven Design Workflow (DOSBTS-side)

## Summary

Stand up a Figma-first design handoff for DOSBTS: document the prototype→implement workflow (a substantive summary in `CLAUDE.md` plus the full procedure in `docs/design-system.md`), add a drift-guard test that pins the hand-mirrored eiDotter tokens, establish a `docs/design-frames/` convention for committed frame snapshots, and — once the upstream Figma library exists — prove the workflow end-to-end on one screen. Mostly docs + one test. Implements the DOSBTS-side of Linear DMNC-791 (see origin: docs/brainstorms/2026-06-18-prototype-driven-design-workflow-requirements.md).

---

## Problem Frame

Design specs reach implementation as lossy prose, which multiplies round-trips on dense screens (overview, chart, marker lane). Separately, the design system is hand-mirrored from eiDotter into `Library/DesignSystem/AmberTheme.swift` with no guard against drift — and `docs/design-system.md` has already drifted on both axes: its color table lists `amberDark #CC8C00`, `cgaGreen #00AA00`, `dosBlack #0A0A0A`, `amberMuted #594F47`, and a stale `dosGray` token, while the code has `#9a5700`, `#55ff55`, near-black, `#555555`, and no `dosGray`; its typography table lists `title`/`header`/`data` tokens that do not exist in `DOSTypography.swift` (the real members are `displayMedium`, `bodyLarge`, `body`, `bodySmall`, `glucoseHero`, `caption`, `button`, `tabBar`). This plan settles how DOSBTS *uses* the upstream (DMNC-802) Figma library and closes the immediate drift with a value-pin test plus a doc reconcile.

---

## Requirements

Carried from the origin requirements doc.

**Handoff workflow**
- R1. Dense or net-new screens use a Figma frame as design source-of-truth; implementation matches the frame, not prose.
- R2. Small, low-density changes stay prose-driven — no frame required.
- R3. Claude reads the frame live via the figma MCP at implementation time.
- R4. Each Figma-driven change links the frame and commits an exported snapshot to the PR as a durable record.
- R5. The committed snapshot is implementation-sufficient (image + key measurements/tokens) so a no-MCP session can still implement.
- R6. Implementation is verified by screenshotting the build against the frame.

**Token consumption**
- R7. Continue hand-mirroring eiDotter tokens in `Library/DesignSystem/` for now (not blocked on DMNC-801).
- R8. A drift-guard test pins the mirrored values and fails on accidental local edits. Acknowledged: a *local pin*, not upstream-divergence detection (that waits for DMNC-801).
- R9. Migrate to DMNC-801's generated tokens when it lands (deferred).

**Documentation & trial**
- R10. The workflow is documented so a fresh, CLAUDE.md-only session can act on it: a substantive summary in CLAUDE.md's Design System section plus the full procedure in `docs/design-system.md` (this refines origin R10's "documented in CLAUDE.md" — see KTD3).
- R11. Prove the workflow end-to-end on one dense screen before declaring it the default.

---

## Planning decisions beyond the brainstorm

- **Reconcile scope expanded** — the brainstorm did not ask to fix `docs/design-system.md`, but the prose tables are drifted on colors *and* typography (Problem Frame), so U2 reconciles both as the on-theme cleanup this initiative is about. Confirmed with the requester during the scope checkpoint.
- **R10 home refined** — origin R10 said "documented in CLAUDE.md"; the plan keeps the full procedure in `docs/design-system.md` (repo convention) but makes the CLAUDE.md addition a substantive, independently-actionable summary, not a bare pointer, so R10's intent (the one file Claude reads at session start carries the workflow) still holds.
- **U4 is a gated follow-on, not a deliverable of this ticket** — the end-to-end trial (R11) is blocked on the upstream eiDotter Figma library (DMNC-802); U1–U3 are this ticket's deliverables, and the trial is tracked as the first Figma-driven feature once 802 exists.

---

## Key Technical Decisions

- KTD1. The drift-guard **extends the existing token-pin pattern** in `DOSBTSTests/AmberChipTests.swift` (`CaptionLegibilityTests` pins `amber` fully and `amberDark`'s red+green channels via `UIColor` RGB extraction at 0.001 tolerance) — not new test infrastructure. Note the existing `amberDark` pin omits its blue channel; U1 completes it rather than assuming full coverage.
- KTD2. Expected-values source is a **hardcoded table** seeded from the current `AmberTheme.swift` values (consistent with the existing pins), not a live eiDotter fetch. This is a local pin (catches local edits); true upstream-divergence detection migrates to DMNC-801's generated tokens (R9). Naming it "drift-guard" is aspirational until 801 — the comment must say so to avoid false confidence.
- KTD3. The workflow procedure lives in **`docs/design-system.md`** (the prose home), and CLAUDE.md's Design System section gets a **substantive summary** (when the workflow applies, the frame→implement→verify loop, the platform checklist pointer) — not a bare two-line link — so a CLAUDE.md-only session can act without opening another file. This is a conscious refinement of origin R10 (KTD recorded in Planning decisions). The procedure includes a **Platform Constraints checklist** any frame must satisfy (`dosNavigationTitle` for nav titles, `safeAreaInset(.bottom)` for persistent bars, unwrapped root `TabView`, no real white).
- KTD4. Committed frame snapshots live in **`docs/design-frames/`** — outside the `App/`/`Library/`/`Widgets/` sync roots, so no widget-target exclusion is needed — as a PNG optimized via the **manual Pillow script** documented in `docs/solutions/best-practices/png-screenshot-optimization-via-pillow-20260422.md` (it is a script, not an automated pipeline), plus a short companion spec (R5's measurements/tokens).
- KTD5. **Reconcile both stale tables** in `docs/design-system.md` against the code: the color table (`amberDark`→#9a5700, `amberLight`→#fdca9f, `cgaGreen`→#55ff55, `cgaCyan`→#55ffff, `cgaRed`→#ff5555, `dosBlack`→near-black, `amberMuted`→#555555 neutral gray; remove the stale `dosGray`; add the `iobBolus`/`iobBasal` tokens) AND the typography table (remove the nonexistent `title`/`header`/`data` rows; add `displayMedium`/`bodyLarge`/`tabBar`; fix `button` to 17pt semibold). The drift this initiative targets lives in both tables.
- KTD6. **Sequence execution after DMNC-772 merges** — U1 touches `project.pbxproj` (new test file) and U2 touches CLAUDE.md, both of which the concurrent 772 work also touches; running them in parallel worktrees would create merge conflicts. The R11 trial (U4) is *additionally* gated on DMNC-802's eiDotter Figma library existing; until the trial passes, the workflow is documented as **provisional**.

---

## Implementation Units

U1–U3 are the deliverables of this ticket. U4 is a gated follow-on (see Planning decisions).

### U1. Token drift-guard test

- Goal: pin the hand-mirrored token values so an accidental local edit fails the suite.
- Requirements: R7, R8.
- Dependencies: none (sequence after 772 merges for the shared `project.pbxproj`).
- Files: `DOSBTSTests/DesignTokenPinTests.swift` (new), `DOSBTS.xcodeproj/project.pbxproj` (manual group + `PBXSourcesBuildPhase` registration — the tests target is not file-system-synchronized).
- Approach: mirror `CaptionLegibilityTests` — resolve `UIColor(AmberTheme.x)`, extract RGB, assert each component within `0.001` of the expected value. Pin every named static `AmberTheme` color not already fully pinned: `amberLight`, `amberPressed`, `amberMuted`, `cgaGreen`, `cgaCyan`, `cgaRed`, `cgaMagenta`, `cgaWhite`, `dosBlack`, `dosBorder`, `cardBackground`, `iobBolus`, `iobBasal` (and any other static color members present). Add `amberDark`'s **blue channel** (the existing pin covers only red+green); do not otherwise re-pin `amber`/`amberDark`. The computed-blend tokens (`glucoseLowBuffer`/`glucoseRising`/`glucoseHighBuffer`) are derived via interpolation — explicitly out of pin scope. Add key `DOSTypography` sizes (`displayMedium`, `glucoseHero`, `body`, `caption`, `button`, `tabBar`) and the `DOSSpacing` values. Seed expected values from the current `AmberTheme.swift` (KTD2). Comment frames the intent: eiDotter is the source; never copy raw hex; a failure means re-run the eiDotter→AmberTheme adaptation; and the guard is a *local pin*, not upstream-sync, until DMNC-801.
- Patterns to follow: `DOSBTSTests/AmberChipTests.swift` (`CaptionLegibilityTests`); no `makeTestDefaults()` needed (no `AppState`).
- Execution note: the unit's deliverable IS the test; write the assertions directly against the tokens.
- Test scenarios: Covers AE4 — editing a hex in `AmberTheme.swift` without updating the table fails the suite. Each pinned color's RGB is within 0.001 of expected (including `amberDark`'s blue channel = 0.0); each pinned `DOSTypography` size equals expected; each pinned `DOSSpacing` value equals expected.
- Verification: `@Test` count rises from the current baseline (pbxproj registration landed); the suite passes; a deliberate one-token edit fails it.

### U2. Workflow documentation + stale-table reconcile

- Goal: document the Figma→implement workflow and fix both drifted tables.
- Requirements: R1, R2, R3, R4, R5, R6, R10.
- Dependencies: U3 (so the snapshot convention can be referenced); sequence after 772 merges (shared CLAUDE.md).
- Files: `docs/design-system.md`, `CLAUDE.md`.
- Approach: add a "Prototype-Driven Design Workflow" section to `docs/design-system.md` covering: when it applies (dense/new screens vs prose for small changes, R1/R2); Figma frame as source-of-truth; live MCP read + committed snapshot in `docs/design-frames/` (R3/R4); the no-MCP fallback implementing from the snapshot+spec (R5); verify-by-screenshot (R6); the eiDotter token-consumption flow (PORT/SKIP/EVALUATE → mirror into `AmberTheme.swift` → update the drift-guard expected value); and the Platform Constraints checklist (KTD3). Reconcile **both** the color table and the typography table per KTD5. Add a substantive, independently-actionable summary to CLAUDE.md's Design System section (KTD3), not a bare pointer. Mark the workflow **provisional until trialed (U4)**, and note what removes the marker (a passing U4 trial).
- Patterns to follow: the `docs/solutions/` → CLAUDE.md pointer convention (extended here to a fuller summary per R10); the iOS-26 Liquid Glass gotchas doc for the platform checklist.
- Test scenarios: Test expectation: none — documentation. (The color-token table's correctness is enforced by U1's test; typography/spacing correctness is enforced by U1's size/spacing pins.)
- Verification: the doc covers flow + fallback + token-consumption + platform checklist; both tables match the code; CLAUDE.md's summary is actionable on its own; the provisional marker (and its removal trigger) is present.

### U3. Snapshot convention (`docs/design-frames/`)

- Goal: establish where and how committed design-frame snapshots live, and make the no-MCP fallback real.
- Requirements: R4, R5; supports AE3.
- Dependencies: none.
- Files: `docs/design-frames/README.md` (new).
- Approach: create `docs/design-frames/` with a README defining: the PNG export of the target frame (optimized via the manual Pillow script at `docs/solutions/best-practices/png-screenshot-optimization-via-pillow-20260422.md` before commit), a short companion spec capturing the key measurements/tokens so it's implementation-sufficient without live MCP (R5/AE3), and a naming convention keyed to the issue/screen. Sits outside the sync roots, so no widget-target exclusion is required.
- Patterns to follow: the `docs/solutions/` directory convention; the Pillow PNG-optimization script.
- Test scenarios: Test expectation: none — directory + convention doc.
- Verification: the folder + README exist; the convention is unambiguous enough that a first snapshot + spec could be dropped in without further decisions, and that spec would be enough to implement the screen without a live MCP (AE3's precondition).

### U4. End-to-end trial on one screen (gated follow-on)

- Goal: prove the workflow once, then flip the docs from provisional to default (R11). Not a deliverable of this ticket — tracked as the first Figma-driven feature once its blockers clear.
- Requirements: R11, R6; verifies AE3 in practice.
- Dependencies: U1, U2, U3. Blocked-on (external): DMNC-802's eiDotter Figma library existing, DMNC-772 merged, the figma MCP connected, and a chosen dense screen.
- Files: the trial screen's view file(s) + a committed snapshot + spec under `docs/design-frames/` (determined at trial time); `docs/design-system.md` (remove the provisional marker on success).
- Approach: pick one dense or net-new screen, design its frame in the eiDotter Figma library (the DOSBTS app file, DMNC-1119), run the full workflow (live MCP read → implement → commit snapshot → screenshot-verify against the frame), then remove the "provisional" marker from the docs. Exercising the no-MCP fallback at least once here also confirms AE3. If 802's library isn't ready, this stays parked — U1–U3 land independently and the workflow remains provisional until then.
- Patterns to follow: the workflow documented in U2; the verify-by-screenshot loop.
- Test scenarios: the trialed screen carries whatever tests its own feature warrants (decided at trial time). Test expectation for *this unit*: none beyond the trial screen's feature tests — the unit's success criterion is the workflow running cleanly end-to-end, not a fixed test.
- Verification: one screen implemented from a Figma frame with a committed snapshot in `docs/design-frames/`; the docs no longer carry the provisional qualifier.

---

## Scope Boundaries

**Deferred for later** (from origin)
- Migrating token consumption to DMNC-801's auto-export (R9) and retiring the hand-mirror.
- DOSBTS's participation in the broader DS governance/taxonomy (DMNC-916, DMNC-1001).

**Outside this plan (eiDotter-side, consumed not built here)**
- Building the Figma library itself (DMNC-802).
- The eiDotter→iOS token export mechanism (DMNC-801).
- Re-deciding the Figma library choice.

---

## Risks & Dependencies

- The R11 trial (U4) is gated on DMNC-802's eiDotter Figma library existing; until then it can't run and the workflow stays provisional. U1–U3 are independent and land first. Risk: the "provisional" marker lingers if 802 slips — U2 names the removal trigger so it isn't forgotten.
- Execution sequencing: U1 (`project.pbxproj`) and U2 (CLAUDE.md) overlap files the concurrent DMNC-772 work also touches — land 791 after 772 merges, or expect manual conflict resolution. This plan is authored on `main`; its own execution branch is `dmnc-791`.
- eiDotter-source uncertainty: the drift-guard pins the *current code values* as the baseline; whether those match eiDotter's published values isn't verifiable in-repo until DMNC-801. The U2 reconcile updates `docs/design-system.md` to match the code, not necessarily to eiDotter. The test comment must say so (KTD2) to avoid false confidence.
- figma MCP availability at implementation time (R3) — the no-MCP fallback (snapshot + spec, R5/AE3) covers the gap.

---

## Open Questions

Deferred to implementation:
- The exact snapshot companion-spec format (redline export vs a short markdown spec sheet vs a Figma Dev Mode export) — this determines whether the no-MCP fallback (R5/AE3) is genuinely sufficient.
- Which `DOSSpacing` values are "key" — the spacing enum's constants are all trivial, so pinning all of them is reasonable.
- Which screen is the U4 trial — depends on what's ready when 802's library lands.
- Whether to later migrate the drift-guard's expected values to a vendored eiDotter token JSON (alongside DMNC-801).

---

## Sources & Research

- Existing value-pin pattern: `DOSBTSTests/AmberChipTests.swift` (`CaptionLegibilityTests`) pins `amber` fully and `amberDark`'s red+green via `UIColor` RGB extraction at 0.001 tolerance (blue channel uncovered — U1 completes it).
- Token source: `Library/DesignSystem/AmberTheme.swift` (header: "eiDotter CGA Amber Design System – iOS Token Mapping / Source: github.com/CinimoDY/eiDotter"), `DOSTypography.swift` (members: `displayMedium`/`bodyLarge`/`body`/`bodySmall`/`glucoseHero`/`caption`/`button`/`tabBar`), `DOSSpacing.swift`. Drifted prose: `docs/design-system.md` — both the color table and the typography table are out of sync (U2 reconciles).
- Learnings (`docs/solutions/`): `build-errors/xcode-filesystem-synchronized-migration-20260422.md` (manual test-file pbxproj registration), `best-practices/cross-repo-backport-workflow-20260418.md` (PORT/SKIP/EVALUATE token-mirror vocabulary; "never copy raw hex"), `best-practices/ios-26-liquid-glass-theming-gotchas.md` (the platform-constraints checklist), `best-practices/png-screenshot-optimization-via-pillow-20260422.md` (the manual Pillow PNG script for committed frames).
- Cluster (Linear): DMNC-802 (eiDotter Figma library — gates U4), DMNC-801 (token export — future R9), DMNC-916/DMNC-1001 (taxonomy/governance — out of scope), DMNC-1119 (DOSBTS app Figma file — the frame home).
- User tooling: figma MCP (figma-console) + the ds-component-builder / figma-design / eidotter-adoption skills. eiDotter is a separate repo (github.com/CinimoDY/eiDotter).
