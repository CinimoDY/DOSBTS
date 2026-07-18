---
title: "Parallel worker fan-out for independent dogfood fixes: plan, dispatch, review, merge train, integrate"
date: "2026-07-18"
category: best-practices
module: "development workflow / multi-agent orchestration"
problem_type: best_practice
component: development_workflow
severity: medium
applies_when:
  - "Multiple independent, well-scoped fixes are ready to ship as one batch, each with its own pre-written checkbox plan doc in docs/plans/"
  - "Parallel worker subagents execute against the same repo where shared files (CHANGELOG.md, project.pbxproj) guarantee merge conflicts without worktree isolation"
  - "Parallel xcodebuild test runs would collide unless each worker is partitioned onto a different iOS simulator device"
  - "Review findings must round-trip back to the SAME worker via agent messaging, since it still holds full implementation context"
  - "Several branches adding the same repo-root file must merge as an ordered train (most-isolated-first) before a single full-suite run and deploy"
resolution_type: workflow_improvement
related_components:
  - tooling
  - testing_framework
tags:
  - parallel-subagents
  - orchestration
  - git-worktree
  - model-tiering
  - simulator-partitioning
  - merge-train
  - review-roundtrip
  - plan-driven-execution
---

# Parallel worker fan-out for independent dogfood fixes: plan, dispatch, review, merge train, integrate

## Context

A solo maintainer dogfooding a TestFlight app comes back from a session with several independent UX complaints at once. Fixing them serially wastes the afternoon; fixing them on one branch entangles review and rollback — a regression in one fix holds all the others hostage. The repo already has the two prerequisites this pattern leans on: a plans-first culture (worker-executable checkbox plan docs under `docs/plans/`) and worker-agent conventions (bounded-brief executors that implement a plan faithfully without inventing scope).

The pattern turns the batch into a small assembly line: one standalone plan per fix, one isolated worker per plan running in parallel, one adversarial reviewer per PR with fixes routed back to the originating worker, a mechanical most-isolated-first merge train, and a single integration test run on the combined result before shipping.

Empirical grounding: DOSBTS shipped four dogfood fixes as Build 132 in one afternoon this way (2026-07-18). The four plans landed as one commit (`docs(plans): four dogfood-feedback hand-off plans`, files `docs/plans/2026-07-18-{lists-single-header,insulin-batch-entry,marker-detail-selective-edit,zoom-aware-marker-consolidation}-plan.md`); the four PRs (#107–#110) merged within about eleven minutes of each other; `CHANGELOG.md`'s `[Build 132] — 2026-07-18` block carries all four entries (DMNC-1413–1416). All four branches touched `CHANGELOG.md`; two also shared `RootSheetContent.swift`/`ContentView.swift` — exactly the conflict profile the merge-train phase is designed for.

## Guidance

### Phase 1 — Plan: one standalone doc per fix

Write one checkbox plan document per fix, plus one tracker issue each that preserves the user's complaint **verbatim** (the verbatim quote is the source of truth for intent — it settles scope arguments later). Each plan must be executable by a worker with **zero session context**:

- **Verified findings with file:line anchors.** Not "the section header lives somewhere in SharedViews" but "Chevron #1: header `Section(header: HStack { ... })` (lines 37–52)" — the shipped `docs/plans/2026-07-18-lists-single-header-plan.md` anchors every claim this way, down to the reducer pin test line range that must survive untouched.
- **Exact interfaces.** If a component's init signature changes, the plan spells out the new signature so the worker doesn't design it.
- **Test-first steps and verification commands.** Checkbox tasks, named test suites to run, and an end-to-end simulator verification script ("Tap the header → expands, chevron flips…").
- **Global constraints / out-of-scope line.** Behaviors that must not change, persisted keys that must not change, and where the fix stops.

The plan-writing pass is also where the orchestrator does all the codebase reading. Workers should navigate by the plan's anchors, not re-explore.

### Phase 2 — Dispatch: one worker per plan, in parallel

Dispatch one worker subagent per plan simultaneously. Each dispatch needs five things:

1. **Git worktree isolation — mandatory when branches share files.** All four Build 132 branches touched `CHANGELOG.md`; two shared Swift files. Workers editing a shared checkout would stomp each other's working tree. One worktree per worker, one branch per worktree, all based on `main`.
2. **A unique iOS simulator per worker.** Parallel `xcodebuild test` runs against the same simulator device collide (booted-state races, install clobbering). Assign each worker its own named device up front.
3. **Model tiered to plan difficulty.** Well-specified mechanical plans go to a cheaper/faster sonnet-class model; judgment-heavy plans (novel geometry, interaction design calls) get an opus-class model. The plan quality is what makes the cheap tier safe.
4. **The executor protocol inlined in the prompt:** execute the plan faithfully; read files before editing; record any deviation in `IMPLEMENTATION_NOTES.md`; never claim success without showing command output; commit, push, and open the PR per the brief.
5. **Sibling-conflict rules inlined:** base only on `main`; conflicts with sibling branches are the orchestrator's problem at merge time; **never** rebase onto or merge sibling work — that converts a planned mechanical conflict phase into an unplanned dependency graph.

### Phase 3 — Review: adversarial pass per PR, fixes back to the same worker

Run one adversarial reviewer subagent per PR, producing severity-ranked findings and explicit clean-confirmations (a reviewer that only lists problems can't distinguish "checked and fine" from "didn't look").

Send **all** findings back to the **same worker that wrote the PR** — its context (plan, file anchors, decisions already made) is intact, so fixes are cheap and correct there. Fixing in the orchestrator or a fresh agent re-pays the whole context ramp and risks contradicting the worker's in-flight decisions.

What the review pass actually catches, empirically: across the four Build 132 PRs there were zero P1s and exactly one P2 each — and every P2 was an interaction-timing or hit-geometry bug invisible to unit tests (an occluded toast, double-tap reentrancy, `contentShape`-before-`frame` modifier ordering, overlapping hit rects). That class of bug is precisely why the adversarial pass exists; the unit suites all passed before review.

### Phase 4 — Merge train: most-isolated-first, conflicts as a mechanical phase

Before merging anything, have each worker move its `IMPLEMENTATION_NOTES.md` content into the PR body and `git rm` the file — N branches each adding the same root-level file is a guaranteed N-way conflict for zero benefit.

Then merge in most-isolated-first order (fewest shared files first; the Build 132 train ran #109 → #110 → #108 → #107). Per branch:

1. Check out the branch, merge `main` into it, resolve conflicts locally.
2. **`CHANGELOG.md` `[Unreleased]` conflicts EVERY time** — this is mechanical, not alarming: keep all entries from both sides, grouped under Added/Changed/Fixed. (The reactive per-conflict playbook lives in [parallel-worktree changelog collisions](../workflow-issues/parallel-worktree-devjournal-changelog-collisions.md).)
3. **`project.pbxproj` usually auto-merges** when both branches registered new test files — but auto-merge of a plist-shaped file must be verified: run `plutil -lint` on it before trusting the result.
4. **If two branches share Swift files, build the combined branch before merging** — a textually clean merge can still be semantically broken.
5. Squash-merge the PR, move to the next branch.

Expect GitHub to report a transient "Base branch was modified" immediately after the previous squash-merge — its mergeability computation lags. Just retry (or poll briefly).

### Phase 5 — Integrate and ship

Run the **full test suite once on the final merged `main`**. This is not redundant: each branch was only ever tested in isolation; the four-way combination was never tested until this moment, and file-level merges cannot detect semantic conflicts (two fixes that each pass alone but interact through shared state). Only after the combined suite passes: bump the build, promote `[Unreleased]` to `[Build N]`, deploy.

The deploy tail has its own documented hazards: build numbering can drift when ASC auto-manages it (see [ASC build-number drift](asc-auto-managed-build-numbers-drift-20260621.md)), and the release-notes step hangs when run headless without the TTY guard (see [headless editor hang](../logic-errors/asc-release-notes-headless-editor-hang.md)).

After the train: remove the worktrees and force-delete the squash-merged local branches — parallel cycles mass-produce exactly the stale-artifact class that later misleads exploration (see [stale workspace artifacts](../workflow-patterns/stale-workspace-artifacts-mislead-exploration-20260712.md)).

### Failure modes to expect (all observed in the Build 132 run)

- **A worker stops itself "awaiting a build notification" that will never fire.** Subagents sometimes park on an event that has no delivery mechanism in their harness. Nudge the worker to run verification in the foreground and to not stop until the PR exists.
- **Newly-added agent-definition files are not dispatchable in an already-running session** — the agent registry loads at startup. Fall back to a generic agent with an explicit model override and the full executor protocol inlined in the prompt; the behavior is equivalent.
- **Back-to-back squash merges race GitHub's mergeability computation.** Poll the PR's merge state or sleep briefly between merges rather than hammering the merge button.

## Why This Matters

- **Wall-clock ≈ slowest worker, not the sum.** Four fixes that would serialize into a multi-day queue collapse into one afternoon; the Build 132 merge train itself took about eleven minutes.
- **Review quality stays high** because each PR is small and single-purpose; a reviewer can be genuinely adversarial about one interaction instead of skimming four.
- **The same-worker fix round exploits retained context** — findings turn into correct fixes in minutes because the worker still holds the plan and its own decisions.
- **Conflicts become a planned, mechanical phase** (CHANGELOG grouping, pbxproj lint, shared-file build) instead of a mid-merge surprise that derails the day.
- **The one integration run catches what file-level merges can't** — semantic conflicts between individually-green branches.

## When to Apply

Apply when **all** of these hold:

- Three or more independent, well-specified fixes, each touching mostly-disjoint code.
- Plans can be written to be executable without session context (findings verifiable, interfaces specifiable up front).
- The repo supports isolated verification per worker (worktrees + per-worker simulators/devices/DB instances).

Do **not** apply for:

- **Exploratory or entangled work** — if the fixes interact by design, parallel workers just move the integration problem later and make it worse.
- **A single large feature** — there is no parallelism to exploit; one worker with one plan is simpler.
- **Plans that would need constant orchestrator clarification** — if the plan can't stand alone, the dispatch overhead exceeds the serial cost. Fix the plan or do the work directly.

## Examples

**Worktree-per-worker setup** (one branch per plan, all based on `main`):

```bash
git worktree add ../DOSBTS-wt-lists   -b feat/lists-single-header main
git worktree add ../DOSBTS-wt-insulin -b feat/insulin-batch-entry main
git worktree add ../DOSBTS-wt-marker  -b feat/marker-selective-edit main
git worktree add ../DOSBTS-wt-zoom    -b fix/zoom-aware-consolidation main
# each worker prompt names its own worktree path AND its own simulator, e.g.:
#   worker A: -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
#   worker B: -destination 'platform=iOS Simulator,name=iPhone 17'
# cleanup after the train:
git worktree remove ../DOSBTS-wt-lists  # etc.
```

**Sibling-conflict clause to inline in every worker prompt:**

> Base your branch only on `main`. Sibling branches exist and will conflict with yours in `CHANGELOG.md` (and possibly shared Swift files) — that is expected and is the orchestrator's problem at merge time. Never rebase onto or merge sibling work. Before the merge train, move your `IMPLEMENTATION_NOTES.md` content into the PR body and `git rm` the file.

**Merge-train loop** (per branch, most-isolated-first):

```bash
git checkout feat/lists-single-header
git merge main
# CHANGELOG.md conflicts every time — keep BOTH sides' [Unreleased] entries,
# grouped under Added/Changed/Fixed, then:
git add CHANGELOG.md
# pbxproj usually auto-merges when both branches registered test files — verify:
plutil -lint DOSBTS.xcodeproj/project.pbxproj
# if this branch shares Swift files with an already-merged sibling, build first:
xcodebuild -project DOSBTS.xcodeproj -scheme DOSBTSApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build
git commit && git push
gh pr merge 109 --squash
# "Base branch was modified" right after the previous merge is transient — retry:
sleep 20 && gh pr merge 110 --squash
```

**Integration gate before shipping** (the combination was never tested until now):

```bash
git checkout main && git pull
xcodebuild test -project DOSBTS.xcodeproj -scheme DOSBTSApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
# only then: bump build, promote [Unreleased] → [Build N], deploy
```

**What "executable without session context" looks like:** see `docs/plans/2026-07-18-lists-single-header-plan.md` — verbatim user feedback as the intent contract, verified findings with file:line anchors ("the `if collapsed, collapsible` branch (55–73) renders a `Button` with the teaser text"), the exact new init signature, global constraints naming persisted keys and pin-test line ranges that must not change, checkbox tasks, and a numbered end-to-end simulator verification script.

## Related

- [Parallel-worktree devjournal/CHANGELOG collisions](../workflow-issues/parallel-worktree-devjournal-changelog-collisions.md) — the reactive conflict-resolution playbook this pattern's merge train absorbs proactively.
- [Autonomous overnight PR stack](autonomous-overnight-pr-stack-20260424.md) — the serial predecessor (branch per issue, merge between, one bundled build); use it for unattended runs, this pattern for attended fan-out.
- [Hand off before the execution phase](hand-off-before-execution-phase-20260425.md) — the context-budget rationale for executing in fresh contexts; the bounded-brief executor protocol is its per-worker evolution.
- [Headless editor hang in the release-notes step](../logic-errors/asc-release-notes-headless-editor-hang.md) and [ASC build-number drift](asc-auto-managed-build-numbers-drift-20260621.md) — the deploy-tail hazards after the train.
- [Stale workspace artifacts mislead exploration](../workflow-patterns/stale-workspace-artifacts-mislead-exploration-20260712.md) — why the teardown step (worktrees + squash-merged branches) is not optional.
