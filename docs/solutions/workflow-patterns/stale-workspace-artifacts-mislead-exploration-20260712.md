---
module: "workspace / planning workflow"
date: "2026-07-12"
problem_type: workflow_pattern
component: exploration
severity: medium
symptoms:
  - "Exploration agents reported the April 2026 ce-code-review findings (.context/compound-engineering/ce-code-review/) as unapplied open work — every finding had been fixed and test-pinned months earlier"
  - "The June 11 branches feat/hig-wwdc26-adoption and fix/bar-strip-polish were reported as in-flight, ready-to-merge work — their features shipped via later PRs on main"
  - "A planning session almost queued 'IOB model hardening' as a top-priority work item based on the stale artifacts"
root_cause: stale_artifacts
resolution_type: process_change
tags:
  - exploration
  - planning
  - stale-artifacts
  - code-review-artifacts
  - branches
---

## Problem

Workspace artifacts persist after the work they describe is finished: `.context/` review JSONs stay on disk after their findings are fixed, branches stay in `git branch` output after being superseded by other PRs, and memory/plan notes describe queues that have since shipped. Exploration (human or agent) reads these as *current state* and reports phantom open work.

## What happened (2026-07-10 planning session)

Three independent explorer-agent claims were disproven by reading current source:

1. "IOBCalculator P2 invariant violation unapplied" — `IOBCalculator.swift` already had `peakSafetyCeilingRatio = 0.49` + named constants, and `IOBCalculatorTests` pinned the 120-min boundary case.
2. "feat/hig-wwdc26-adoption has ~2500 LOC ready to merge (U6–U9 pending)" — GlucoseStatusBar/SheetCoordinator shipped on main via later PRs; the branch is superseded, not in-flight.
3. CLAUDE.md's `Section(header: Label(...))` phrasing had zero grep hits — the live pattern is `header: {` trailing closures (48 sites), so a literal-phrase grep concludes "already migrated" wrongly.

## Rule

Treat `.context/` artifacts, non-main branches, and memory/plan notes as **unverified claims with a timestamp**, never as current state. Before planning from them:

- For review findings: open the cited file at the cited line on current `origin/main` and check whether the fix is present (and test-pinned).
- For branches: `git merge-base --is-ancestor <branch> main`, then check whether the branch's *feature* exists on main by another route (grep for its symbols) — unmerged ≠ pending.
- For CLAUDE.md/memory phrasing about code patterns: grep the stated pattern; zero hits means the description drifted, not that the work is done.

Delete disproven artifacts when found (this session removed the stale ce-code-review directory) so the next exploration can't be misled by them.
