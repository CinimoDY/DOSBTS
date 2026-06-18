---
title: Parallel agent worktrees collide on shared devjournal session dir and CHANGELOG Unreleased block
date: 2026-06-13
category: workflow-issues
module: devjournal / release workflow
problem_type: workflow_issue
component: development_workflow
severity: medium
applies_when:
  - "Merging a PR authored in a parallel Claude worktree after a TestFlight deploy promoted [Unreleased]"
  - "Multiple agent sessions ran on the same project on the same day (devjournal keys sessions by project+date)"
  - "A rebase reports add/add conflicts under .devjournal/sessions/ or content conflicts in CHANGELOG.md"
tags: [git-worktree, rebase-conflicts, devjournal, changelog, parallel-agents, release-process]
---

# Parallel agent worktrees collide on shared devjournal session dir and CHANGELOG Unreleased block

## Context

Two PRs (DMNC-1044 / PR #57, DMNC-1045 / PR #58) were authored by Claude sessions in separate git worktrees on the same day a TestFlight deploy happened on main. Both hit the identical conflict set on rebase:

- Each worktree session committed devjournal artifacts (`session-report.md`, `decisions.md`, `themes.md`, `manifest.json`) into the **same dated directory** `.devjournal/sessions/dosbts-2026-06-12/`, which main's wrap-up also committed with different content → add/add conflicts.
- Each added its CHANGELOG entry under `[Unreleased]` against the **pre-deploy layout**; after main promoted `[Unreleased]` → `[Build 102]`, the hunk no longer applied → content conflict, and the entry needed re-homing so it ships with the *next* build.
- Bonus trap: the worktree held **untracked** devjournal files that main now tracks, which blocks `git rebase` checkout entirely ("untracked working tree files would be overwritten").

Root cause worth knowing: devjournal keys sessions by `<project>-<date>`, so any two parallel worktrees on the same day collide **by construction** — this will recur until session dirs are keyed per-branch or per-worktree.

## Guidance

Resolution playbook (applied successfully on both PRs):

1. **Before rebasing**, back up and remove the worktree's untracked devjournal files that collide with tracked paths on main (they hard-block the rebase checkout): `cp -R .devjournal/sessions/<dir> /tmp/backup/ && rm` the colliding files.
2. `git rebase origin/main`, then resolve:
   - **Shared devjournal files** (`decisions.md`, `themes.md`, `session-report.md`): keep **main's** version (`git checkout --ours` during rebase — "ours" is main).
   - **Preserve the branch's content** as sibling files: `session-report-dmnc-NNNN.md`, `decisions-dmnc-NNNN.md` (recover the branch version via `git show :3:<path>` or from the pre-rebase backup).
   - **manifest.json**: take main's, append the branch's issue ID to `linearIssues`.
   - **CHANGELOG.md**: move the branch's entry under the **new empty `[Unreleased]`** above the promoted `[Build N]` block, and tag it `— DMNC-NNNN, PR #NN`.
3. Full simulator build in the worktree before pushing (`xcodebuild ... build`) — rebases can conflict semantically even when git resolves cleanly.
4. `git push --force-with-lease`, wait for GitHub to recompute mergeability (it shows stale `CONFLICTING` right after a force-push), then squash-merge.
5. After a squash merge, delete the local branch with `-D` (git can't detect squash-merged branches as merged).

## Why This Matters

Without the playbook each PR merge after a deploy turns into ad-hoc conflict archaeology, and naive resolution silently destroys session records: taking the branch's devjournal files clobbers main's wrap-up history; taking main's outright loses the branch's session report. The CHANGELOG half matters for release integrity — resolving the conflict in place under the promoted block would falsely attribute the fix to a build that doesn't contain it.

## When to Apply

Any rebase of an agent-worktree branch that touches `.devjournal/sessions/` or `CHANGELOG.md` after main has had a deploy bump or another session's wrap-up. Check `gh pr diff <n> --name-only` for `.devjournal/` paths before merging worktree PRs — that's the early-warning sign.

## Examples

PR #57 resolution: kept main's `session-report.md` (Build 102 wrap-up), preserved the branch's as `session-report-dmnc-1044.md`, manifest gained `"DMNC-1044"`, changelog entry re-homed under `[Unreleased]` → shipped later in Build 103.

## Prevention

- The structural fix is keying devjournal session dirs per branch/worktree (e.g. `dosbts-dmnc-1044-2026-06-12/`) so parallel sessions never share files. Until then, expect and budget for this conflict class on every same-day parallel-worktree merge.
- The deploy-time CHANGELOG cross-check (CLAUDE.md, CHANGELOG section) catches the sibling failure mode where a PR merges with no entry at all.
