---
title: "Autonomous overnight PR stack — ready-to-code issues only, merge-between, single bundled build"
date: 2026-04-24
category: best-practices
module: workflow
problem_type: best_practice
component: workflow
severity: low
applies_when:
  - "Claude is running unattended overnight with auto-mode enabled"
  - "Backlog has a mix of brainstorm-needed and code-ready issues"
  - "Recent TestFlight build is already shipped and issues reference its shipped code"
tags:
  - autonomous-mode
  - pr-workflow
  - testflight
  - triage
  - solo-dev
---

# Autonomous overnight PR stack

## Situation

In a solo-dev iOS app with a TestFlight cadence, the user occasionally hands over a multi-issue queue overnight with instructions to "use superpowers, push through to TestFlight, take screenshots, don't ask permission." The queue typically mixes:

- Issues that need design codesign (brainstorming + visual-companion work)
- Issues that are code-ready (spec + implementation sketch + acceptance criteria in the body)

The temptation is to attack everything in one bundled branch. That produces a big, hard-to-review PR and risks one feature's regression blocking the others. The opposite temptation — branch per issue but keep them all open for the user to review in the morning — defers user feedback for a full day and misses the overnight deployment window.

## Pattern that works

**Branch per issue, merge between, one bundled build at the end.**

Concretely:

1. **Triage by readiness, not priority.** Fetch each queued issue. If the body contains (problem, proposal, implementation sketch, acceptance criteria), it's code-ready — queue for tonight. If it needs design discussion or visual-companion iteration, defer to next interactive session.

2. **Serialise the branches.** For each ready issue:
   - Branch from freshly-synced `main`
   - Implement + tests + CHANGELOG entry under `[Unreleased]`
   - Build (`xcodebuild build`) — don't trust SourceKit "Cannot find type" diagnostics on cross-file types; the real build is authoritative
   - Commit with the conventional `type(scope): subject — DMNC-NNN` format
   - Push, open PR with `gh pr create`, squash-merge with `gh pr merge --squash`
   - Sync local `main`
   - Move to next issue

3. **Bundle the build bump.** After the last feature PR merges, create a separate `chore/bump-to-build-N` branch that:
   - Replaces all four `CURRENT_PROJECT_VERSION = N-1` occurrences → `N` in pbxproj
   - Promotes the accumulated `[Unreleased]` block to `[Build N] — YYYY-MM-DD` with a new empty `[Unreleased]` above
   - Appends `— PR #NN` suffixes to each changelog line
   - PR + squash-merge, then `./deploy.sh`

4. **Close the Linear issues with PR attachments.** After deploy, for each shipped issue: post a summary comment naming the build, attach the PR link, and move to `Done` state via `mcp__plugin_linear_linear__save_issue`.

## Why this shape

- **Branch per issue** gives the user five separately-reviewable PRs in the morning even though they were written in one session. If any of them has a regression, they can be reverted individually without losing the others.
- **Merge between, not stack** avoids rebase conflicts mid-session. The feature PRs are almost always in unrelated files for a feature queue like this (one in `GlucoseView`, one in `ChartToolbar`, one in `FavoriteFood` + store), so fast-forward merges against fresh `main` are clean.
- **Single bundled TestFlight build** is the right dose. Three new features in one build is fine — user reads one CHANGELOG entry with three bullets and tests them in one session. Three separate TF builds would flood their inbox and fragment testing.
- **Issue closeout happens after deploy, not at merge.** The issues move from "Backlog → Done" only when the binary is actually in the user's hand. Between merge and deploy is a purgatory state where main has the change but TestFlight doesn't.

## When to break the pattern

- **The queue is independent enough to fan out** — when the issues are well-specified, mostly-disjoint, and someone is attending the session, the concurrent alternative is [plan-driven parallel worker fan-out](plan-driven-parallel-worker-orchestration.md) (worktrees + per-worker simulators + per-PR review loop): wall-clock ≈ slowest worker instead of the serial sum. This serial stack remains the right shape for unattended overnight runs.
- **One feature touches shared infra another feature also touches** — stack them, because the second feature's diff will be misleading against stale `main`. Rare in a feature queue but common in refactors.
- **The build bump is a hotfix** — skip the separate bump PR, bundle the single fix + bump into one PR.
- **TestFlight isn't available** — deploy.sh can fail (passcode-locked connected device, expired ASC key, simulator build corruption). Fall back to committing the bump + CHANGELOG promotion but not running deploy; user runs it at their next console session.

## Autonomous-mode red flags

- **SSH signing failures** in `git push`: the `sign_and_send_pubkey: signing failed for ED25519` warning from 1Password agent is usually noise — the push itself succeeds via fallback authentication. Verify with `ssh -T git@github.com` (expect "Hi USERNAME! You've successfully authenticated"). Don't switch to HTTPS or kill the 1Password integration based on the warning alone.
- **Computer-use for UI automation** needs a `request_access` dialog that blocks on the user's Mac. If the user is asleep, skip it. Launch screenshots via `xcrun simctl io <udid> screenshot` don't need access and still prove the build is alive.
- **Merging own PR** is a durable shared-state action. Safe only when: (a) the repo has no other maintainers, (b) CI is green, (c) the PR is small and its content was explicitly authorised by the user in the session. Still, prefer `gh pr merge --squash` (reversible via revert PR) over direct push to `main`.
- **Marking issues Done without PR attachment** loses the shipping-audit trail. Always: comment with PR link + build number, *then* move state.

## Related

- `docs/solutions/best-practices/cross-repo-backport-workflow-20260418.md` — pattern for the DOOMBTS ↔ DOSBTS case where changes need to cross repos.
- `CLAUDE.md § CHANGELOG` — the canonical rule for CHANGELOG promotion during build bumps, which this pattern builds on.
