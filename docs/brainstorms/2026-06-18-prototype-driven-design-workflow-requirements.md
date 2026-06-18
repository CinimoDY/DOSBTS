---
date: 2026-06-18
topic: prototype-driven-design-workflow
---

# Prototype-Driven Design Workflow (DOSBTS-side) — Requirements

## Summary

Replace lossy word-level design round-trips with a Figma-first handoff: for dense or net-new DOSBTS screens, the design source-of-truth is a Figma frame in the eiDotter library, which Claude reads live via the figma MCP and implements against, committing an exported snapshot to the PR as the durable record and verifying with screenshots. Token consumption stays hand-mirrored with a drift-guard test until DMNC-801's auto-export lands. The workflow is documented in `CLAUDE.md` and proven on one screen. Implements the DOSBTS-side of Linear DMNC-791.

## Problem Frame

Design specs reach implementation as prose: the user describes a screen, Claude builds it, screenshots come back, they iterate in words. For visual density and pixel-exact work — the overview, the chart, the marker lane — words are too lossy, and the round-trips multiply. The fix is to hand Claude a real design artifact as the source-of-truth instead of a description. The pieces to make that work already exist around DOSBTS (the eiDotter design system, a Figma library proposed in DMNC-802, the user's Figma tooling); this brainstorm settles how DOSBTS *uses* them.

## Key Decisions

- **Scope is the DOSBTS-side workflow + token consumption only.** The Figma library choice is settled upstream by DMNC-802 (Apple's iOS-26 Figma community file reskinned with eiDotter CGA tokens). This brainstorm does not re-decide the library.
- **Figma-first handoff** over HTML prototypes or annotated screenshots — most pixel-exact for the density work that motivated this, and it banks on the eiDotter Figma library.
- **Live MCP read + committed snapshot** over link-only or export-only — Claude reads the frame live for fidelity, and a committed export keeps the design reviewable from the repo later.
- **Hand-mirror + drift guard now** over blocking on DMNC-801 — unblocks the workflow without coupling it to cross-repo eiDotter work; migrate to generated tokens when 801 lands.
- **Per-feature cadence** over default-on — Figma handoff for dense or net-new screens; small tweaks stay prose-driven.
- **DMNC-1119 is the home for DOSBTS app frames** within this workflow — the app's Figma file where these frames are designed, not a separate effort.

## Requirements

**Handoff workflow**
- R1. For dense or net-new screens, the design source-of-truth is a Figma frame in the eiDotter Figma library; the implementation matches the frame, not a prose description.
- R2. Small, low-density changes (single control, copy, logic-only) remain prose-driven — no Figma frame required.
- R3. Claude reads the frame live via the figma MCP (structure, tokens, measurements) at implementation time.
- R4. Each Figma-driven change links the frame from the Linear issue/PR and commits an exported snapshot of the target frame to the PR as a durable record.
- R5. The committed snapshot is implementation-sufficient — it pairs the frame image with the key measurements/tokens needed to implement the screen without a live MCP connection.
- R6. Implementation is verified by screenshotting the built screen and comparing it against the frame.

**Token consumption**
- R7. DOSBTS continues to hand-mirror eiDotter CGA tokens in `Library/DesignSystem/AmberTheme.swift`, `DOSTypography.swift`, and `DOSSpacing.swift` for now — not blocked on DMNC-801.
- R8. A drift-guard test pins the mirrored token values against a documented expected-values table and fails on accidental local edits. Acknowledged limitation: this is a *local pin*, not upstream-divergence detection — true cross-repo sync arrives with DMNC-801.
- R9. When DMNC-801 (eiDotter→iOS token auto-export) lands, DOSBTS migrates to the generated tokens and retires the hand-mirror.

**Documentation & trial**
- R10. The workflow is documented in `CLAUDE.md` (Design System section) once it has been shown to work.
- R11. The workflow is proven end-to-end on one dense screen before it's declared the default.

## Key Flows

- F1. Figma-driven implementation (dense / new screen)
  - **Trigger:** A change qualifies as dense or net-new (R1).
  - **Steps:** Design the frame in the eiDotter Figma library (the DOSBTS app file, DMNC-1119) → link it from the issue → Claude reads it live via the figma MCP → implements against it → commits the exported snapshot + specs to the PR → screenshots the build and compares to the frame.
  - **Covers:** R1, R3, R4, R5, R6.

- F2. No-MCP fallback
  - **Trigger:** The figma MCP is not connected at implementation time.
  - **Steps:** Claude implements from the committed snapshot + specs (R5); fidelity is best-effort and the PR notes that the live frame was not read.
  - **Covers:** R5.

## Acceptance Examples

- AE1. Covers R1, R4. A net-new screen ships with its implementation matching a linked Figma frame, and the frame's exported snapshot is committed to the PR.
- AE2. Covers R2. A copy or single-control tweak ships prose-driven, with no Figma frame.
- AE3. Covers R5, F2. With the figma MCP unavailable, the committed snapshot + specs are sufficient to implement the screen to a reasonable fidelity.
- AE4. Covers R8. Editing a hex value in `AmberTheme.swift` without updating the expected-values table fails the drift-guard test.

## Scope Boundaries

**Deferred for later**
- Migrating token consumption to DMNC-801's auto-export (R9), and retiring the hand-mirror.
- DOSBTS's participation in the broader DS governance/taxonomy (DMNC-916, DMNC-1001).

**Outside this brainstorm (eiDotter-side, consumed not built here)**
- Building the Figma library itself (DMNC-802).
- The eiDotter→iOS token export mechanism (DMNC-801).
- Re-deciding the Figma library choice.

## Dependencies / Assumptions

- The eiDotter Figma library (DMNC-802 Step 1, the iOS-26 reskin) must exist for frames to be designed against. Partial dependency — the workflow can start against whatever component set 802 ships and grow with it.
- The figma MCP is connected at implementation time for the live-read path (R3). This is an assumption; F2 is the fallback when it isn't.
- DMNC-1119 provides the DOSBTS app's Figma file as the frame home.

## Outstanding Questions

Deferred to planning:
- The exact format of the committed snapshot + specs (PNG + redline export? a markdown spec sheet? a Figma Dev Mode export?) and where it lives (PR attachment vs a versioned `docs/design/` or `Prototypes/` folder).
- The drift-guard's expected-values source — a hardcoded table in the test vs a vendored eiDotter token JSON snapshot the test reads.
- Which screen is the end-to-end trial (R11).

## Sources / Research

- Design system (this repo): `Library/DesignSystem/AmberTheme.swift` (header: "eiDotter CGA Amber Design System – iOS Token Mapping / Source: github.com/CinimoDY/eiDotter"), `DOSTypography.swift`, `DOSSpacing.swift`, `Components/`; prose spec `docs/design-system.md`. No `Prototypes/` folder exists yet.
- Cluster (Linear): DMNC-802 (eiDotter Figma mirror — the library this consumes), DMNC-801 (iOS token export — future R9 migration), DMNC-916 (4-tier token taxonomy), DMNC-1001 (DS governance + DOSBTS adoption), DMNC-1119 (DOSBTS Figma file), DMNC-807 + DMNC-793 (prior codesign brainstorms that used the mockup→spec→implement pattern this formalizes).
- User tooling: figma MCP (figma-console), plus the ds-component-builder / figma-design / eidotter-adoption skills. The eiDotter design system is a separate repo (github.com/CinimoDY/eiDotter).
