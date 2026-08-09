---
name: deploy-testflight
description: Run and troubleshoot a DOSBTS TestFlight deploy — deploy.sh mechanics, signing and provisioning gotchas, ASC auto-managed build-number drift, and the release-notes push. Use when shipping a build or diagnosing a failed/renumbered upload.
---

# Deploy to TestFlight

Operational detail for `./deploy.sh`. The **prerequisite safety check and the version/CHANGELOG bump live elsewhere** — see "Before you run this" below.

## Before you run this

1. **Verify there is something to ship.** If nothing user-visible has landed since the last `chore: bump build` commit and `[Unreleased]` is empty, stop and report — do not bump. (Deploy runs at Builds 109 and 125 were aborted after discovering exactly this.) This rule also lives in `CLAUDE.md` because it must be in context whether or not this skill is loaded.
2. **Bump and promote.** `deploy.sh` does **not** auto-bump. Change `CURRENT_PROJECT_VERSION` in `project.pbxproj` (4 occurrences — the `bump-build` skill does this correctly, including leaving the two legacy `GlucoseDirect` entries alone) and promote `[Unreleased]` → `## [Build N] — YYYY-MM-DD` in `CHANGELOG.md` **before** running the script.

## Running it

`./deploy.sh` — uses an App Store Connect API key; `ExportOptions.plist` uses automatic signing.

The script's own order matters:

- **Before archiving** it runs `cp CHANGELOG.md Library/Resources/CHANGELOG.md`, so the in-app "What's New" reflects the shipped build. This is why the `[Unreleased] → [Build N]` promotion has to happen first.
- **After upload** it runs `scripts/asc-release-notes.sh` (fail-soft) to derive the build's TestFlight "What to Test" from the latest `[Build N]` block and push it via the ASC API.
- It leaves the refreshed `Library/Resources/CHANGELOG.md` **uncommitted** — commit it after a successful upload as `chore: sync bundled changelog for Build N`.

## Archive failures

- **Connected iPhone is passcode-locked** → archive fails. Unlock or disconnect it.
- **Provisioning profiles are per-macOS-account.** Deploying from a new account? Archive once from Xcode first to generate them.

## Build numbers drift (ASC auto-manages them)

App Store Connect renumbers silently: re-uploading an already-shipped `CURRENT_PROJECT_VERSION` gets a new number, so git and TestFlight diverge.

- `deploy.sh` runs an ASC pre-flight that aborts **before archiving** if the local build is already on TestFlight.
- The next build should be `max(local, TestFlight latest) + 1`.
- `scripts/asc-release-notes.sh` matches the just-uploaded build **by recency, not by number**, since the ASC number can differ.

Full write-up: `docs/solutions/best-practices/asc-auto-managed-build-numbers-drift-20260621.md`.

## Release notes (`scripts/asc-release-notes.sh`)

Re-runnable standalone: `./scripts/asc-release-notes.sh`.

- Set `ASC_APP_ID` (numeric app id) in your env to enable the push. `ASC_KEY_PATH` / `ASC_KEY_ID` / `ASC_ISSUER_ID` default to the upload credentials.
- Interactive runs open `$EDITOR` for review with a `FOCUS THIS BUILD` / `KNOWN ISSUES` scaffold before pushing. It never writes back to `CHANGELOG.md`.
- **Headless runs (no TTY, no `EDITOR`) skip the review** and push the changelog-derived body without the scaffold. To curate non-interactively, set `EDITOR` to a scripted rewrite. See `docs/solutions/logic-errors/asc-release-notes-headless-editor-hang.md`.
- **Back-to-back deploys less than 30 minutes apart race the notes matcher** (recency window 1800s): the new build's notes can land on the *previous* build. Telltale output line: `ASC build number (N-1) differs from CHANGELOG (N)`. Before re-deploying, check the latest TestFlight build's `uploadedDate` is more than 30 minutes old.
