---
title: "Two implementations of one text-cleaning grammar (Swift parser + shell/perl) — verify parity, and watch perl `\\s*$` eating newlines"
date: 2026-06-20
category: best-practices
module: changelog / deploy
problem_type: best_practice
component: build_and_release
severity: low
applies_when:
  - "The same text-cleaning rule must run in two languages (e.g. a Swift parser for the app + a shell/perl extractor in deploy.sh)"
  - "Reproducing a regex grammar in perl that anchors a strip at end-of-line"
  - "A single source file (CHANGELOG.md) feeds both an in-app surface and a deploy-time surface"
tags: [changelog, perl, regex, shell, parser, single-source-of-truth, deploy]
---

# Two implementations of one grammar — verify parity, and the perl `\s*$` newline trap

## Context

DMNC-1147 (always-on changelog) cleans `CHANGELOG.md` entries — stripping developer metadata (`— DMNC-NNN, PR #NN` and chained / multi-issue / trailing-word variants) and a `{tour:<key>}` marker — in **two** places: a Swift `ChangelogParser` for the in-app "What's New", and a perl one-liner in `scripts/asc-release-notes.sh` for the TestFlight notes. Shell can't call the Swift parser, so the grammar is implemented twice. The risk is drift: the two cleaners diverge and the in-app text no longer matches the pushed release notes.

## What worked

1. **Define the grammar once, in prose, and port it verbatim.** The metadata grammar (known leading token set `DMNC-\d+ | PR #\d+ | R\d+ | AE\d+ | D\d+ | [A-Z]{2,}-\d+`, then issue refs / short lowercase connectors / `(...)` groups / trailing period; **iterative** so chained `— A — B` runs strip but a prose em-dash stops it) lives in the plan's KTD and in code comments in both files. The perl alternation mirrors the Swift `NSRegularExpression` pattern token-for-token.

2. **Cross-check the two outputs before trusting them.** A throwaway check — run the perl extractor on the latest `[Build N]` block, run the Swift parser on the same build (a 3-line `swiftc` harness over `Changelog.swift`), and `diff` the cleaned entries — proved them **byte-identical**. This is cheap (no Xcode build needed; `swiftc -O Changelog.swift harness.swift`) and is the thing that actually justifies the "single source of truth" claim.

## The trap: perl `\s*$` eats the newline

The first cut anchored the metadata strip with `...\.?\s*$//`. In perl `-p` mode, `\s` includes `\n`, and `\s*$` greedily consumes the line's own trailing newline — so every entry that *had* metadata lost its line break and the next bullet concatenated onto it (`...correct a high• Scored meals...`).

Fix: anchor with horizontal whitespace only — `[ \t]*$` instead of `\s*$`. Same for the leading boundary if it must not cross lines. The Swift side didn't have this bug because it splits on `\n` first and trims per line.

```perl
# WRONG: \s*$ eats the trailing newline, collapsing adjacent bullets
1 while s/[ \t]+\x{2014}[ \t]+TOKEN...\.?\s*$//;
# RIGHT: [ \t]*$ leaves the newline intact
1 while s/[ \t]+\x{2014}[ \t]+TOKEN...\.?[ \t]*$//;
```

## Takeaways

- When the same rule must exist in two languages, write the grammar down once and **diff the two implementations' output on real data** — don't eyeball it.
- In perl line mode, prefer `[ \t]` over `\s` for end-of-line anchors so you don't swallow `\n`.
- A pure parser (no I/O, plain Foundation) can be exercised with a standalone `swiftc` harness against the real corpus in seconds — far faster than a full test target build for iterating on a regex grammar.
