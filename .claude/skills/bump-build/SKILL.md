---
name: bump-build
description: Bump CURRENT_PROJECT_VERSION across all 4 pbxproj occurrences and promote CHANGELOG [Unreleased] → [Build N] — YYYY-MM-DD. Use before running ./deploy.sh to ship a TestFlight build.
disable-model-invocation: true
---

# Bump Build

Prepares DOSBTS for a TestFlight deploy by bumping the project version and promoting the CHANGELOG. **Does not run `./deploy.sh` itself** — the user runs that manually afterwards (or via the global `deploy` skill).

## Why this exists

The deploy flow has two coupled, easily-desynced edits:

1. **`CURRENT_PROJECT_VERSION` appears in 4 places** in `DOSBTS.xcodeproj/project.pbxproj` (the `DOSBTSApp` debug/release + `DOSBTSWidget` debug/release configs). All four must match.
2. **CHANGELOG.md `[Unreleased]` must be promoted** to `## [Build N] — YYYY-MM-DD` (em-dash, ISO date) *before* the bump, otherwise entries strand in the wrong build.

There are also two `CURRENT_PROJECT_VERSION = 1;` entries at lines ~726 and ~744 — those belong to the legacy `GlucoseDirect` targets. **Leave those alone.**

## Inputs

Ask the user (or infer from context):
- **target build number** — usually current + 1; offer that as default
- **date** — defaults to today (ISO `YYYY-MM-DD`, use `date +%Y-%m-%d`)

## Steps

### 1. Verify preconditions

```bash
cd /Users/doke/extracode/DOSBTS
git status --short                # working tree should be clean-ish (changes ready to ship)
grep -nE '^## \[Unreleased\]' CHANGELOG.md
grep -c 'CURRENT_PROJECT_VERSION = ' DOSBTS.xcodeproj/project.pbxproj  # expect 6 (4 + 2 legacy)
```

If `[Unreleased]` is empty (no entries beneath it before the next `##`), confirm with the user: maybe this is an internal-only build, or they forgot to add entries.

### 2. Read current version

```bash
grep -m1 'CURRENT_PROJECT_VERSION = [0-9]' DOSBTS.xcodeproj/project.pbxproj | grep -oE '[0-9]+'
```

The 4 non-legacy occurrences should all be the same. If they're already split, halt and report — something is wrong.

### 3. Bump pbxproj (4 occurrences only)

Use `Edit` with `replace_all` on the exact `CURRENT_PROJECT_VERSION = <OLD>;` string. Because the legacy entries are `= 1;`, `replace_all` of `= 96;` (or whatever OLD is) is safe — it won't touch the legacy lines.

```
old_string: CURRENT_PROJECT_VERSION = <OLD>;
new_string: CURRENT_PROJECT_VERSION = <NEW>;
replace_all: true
```

Verify:
```bash
grep -nE 'CURRENT_PROJECT_VERSION = (' DOSBTS.xcodeproj/project.pbxproj | head -10
```
Should show 4× `<NEW>` and 2× `1` (legacy GlucoseDirect targets).

### 4. Promote CHANGELOG

Replace the `## [Unreleased]` header with a new pair: a fresh empty `[Unreleased]` block above, then `## [Build <NEW>] — <DATE>` below. Em-dash is U+2014 (`—`), not a hyphen.

```
old_string: ## [Unreleased]
new_string: ## [Unreleased]

## [Build <NEW>] — <DATE>
```

Verify by reading the first 30 lines of CHANGELOG.md — the new `[Unreleased]` should be empty, the `[Build NEW]` block should hold the entries that were previously under `[Unreleased]`.

### 5. Report

Summarize for the user:
- old build → new build
- date used
- whether CHANGELOG had entries to promote (and a one-line list)
- next step: `./deploy.sh` (and the `git status` so they can decide whether to commit before/after deploy)

## Notes

- **Don't commit** — the user may want to review or amend. Just stage if they ask.
- **Don't run `./deploy.sh`** — that's a separate, explicit user action.
- **Yanked builds** — if the user mentions they're re-bumping after a yank, don't re-promote `[Unreleased]` (it should already be empty); just bump the pbxproj number. Add a `**Yanked.**` note to the prior `[Build N]` block if not already there.
- **Split-cycle**: if entries under `[Unreleased]` describe features that won't actually ship in this build (e.g., behind a feature flag they didn't enable), ask the user before promoting them.
