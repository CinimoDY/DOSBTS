---
title: "App Store Connect auto-manages build numbers — re-uploads silently renumber and desync git from TestFlight"
date: 2026-06-21
category: best-practices
module: deploy
problem_type: best_practice
component: deploy
severity: medium
applies_when:
  - "Running ./deploy.sh / shipping a TestFlight build"
  - "A build number may already have been uploaded (re-run, parallel session, second machine)"
  - "Setting TestFlight 'What to Test' notes via the App Store Connect API"
tags:
  - deploy
  - testflight
  - app-store-connect
  - build-numbers
  - asc-api
---

# ASC auto-managed build numbers → git/TestFlight drift

## What happened (Build 109/110/111, 2026-06-21)

The crashed deploy was re-run with `CURRENT_PROJECT_VERSION = 109`, but **109 was
already on TestFlight** (an earlier session had uploaded it). The re-upload still
"succeeded" — App Store Connect has **automatic build-number management** on for
this app, so instead of rejecting the duplicate it **renumbered the upload to
110**. Result: the archive's `CFBundleVersion` was 109 but ASC registered it as
**110**, leaving git/`CHANGELOG.md` one behind TestFlight.

Two consequences:

1. **Silent drift.** git said 109, TestFlight said 110. The next naive `+1` bump
   (→110) would have collided with the existing 110.
2. **The release-notes automation missed.** `scripts/asc-release-notes.sh` polled
   for the build by `filter[version]=<CHANGELOG number>` — but the ASC number no
   longer matched, so it never found the build and timed out.

## Root causes / gotchas

- **ASC build numbers are not your `CFBundleVersion` once auto-management is on.**
  They are assigned sequentially by ASC; a collision (or any re-upload) advances
  the ASC number independently of git. Never assume `ASC build == CFBundleVersion`.
- **Two App Store Connect API field/filter facts** (both bit the first run of the
  DMNC-1147 notes automation):
  - `/v1/builds` does **not** support `filter[platform]` → `400
    PARAMETER_ERROR.INVALID`. Filter by `filter[app]` (+ `filter[version]`) only.
  - `betaBuildLocalizations` has **no `whatsToTest` attribute** → `409
    ENTITY_ERROR.ATTRIBUTE.UNKNOWN`. The field behind TestFlight's "What to Test"
    is **`whatsNew`**.

## The fix (what's now in the repo)

- **`deploy.sh` pre-flight collision guard** — before archiving, query the latest
  TestFlight build and **abort** if `CURRENT_PROJECT_VERSION <= ASC latest`, with
  a message telling you to bump to `ASC_max + 1`. Best-effort (needs `ASC_APP_ID`);
  a query failure warns and proceeds. This is the check that would have caught the
  double-deploy.
- **`scripts/asc-release-notes.sh` matches by recency, not by number** — it takes
  the newest build for the app uploaded within a 30-min window of the run (the one
  we just uploaded), independent of whatever number ASC assigned, and reconciles
  the notes header to the real ASC build number. Plus the two field fixes above.
- **The deploy skill bumps to `max(local, TestFlight latest) + 1`** instead of a
  blind `local + 1`, so drift self-heals at the next deploy.

## Takeaways

- Before bumping/deploying, **confirm the current number isn't already live on
  TestFlight** (the guard now does this; see also the memory note
  "deploy-verify-build-not-already-shipped").
- When matching "the build we just shipped" against the ASC API, match by
  **recency**, not by a number you control — ASC may have changed it.
- The git build counter is a *suggestion* under auto-management; realign it to
  TestFlight when they drift (a one-off `chore` bump documented in `CHANGELOG.md`).
