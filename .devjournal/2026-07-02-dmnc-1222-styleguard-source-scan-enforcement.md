# DMNC-1222 — StyleGuardTests: Source-Scan Enforcement + Docs Coherence

**Date:** 2026-07-02  
**Branch:** claude/dmnc-1222  
**Part of:** DMNC-1211 (visual consistency refactor umbrella) — **lands strictly last**

## What changed

Added `DOSBTSTests/StyleGuardTests.swift` — a Swift Testing suite that makes design-system drift fail `Cmd+U`. Plus a docs coherence pass so `design-system.md` + `CLAUDE.md` describe only what exists.

The whole umbrella (WP-A…WP-H, PRs #74–#81) swept the codebase clean of raw `.font`, `.foregroundColor`, `Color.black`, `cornerRadius`, `ProgressView()`, inline animation curves, and raw hex. This task freezes those wins so they can't regress silently.

## Mechanism

Unlike `DesignTokenPinTests` (which links app symbols), these guards **read `.swift` sources straight off disk**. `#filePath` resolves the test file, two `deletingLastPathComponent()` hops reach the repo root, and each rule greps its scoped directories with an `NSRegularExpression`.

- **One `@Test` per rule** (8) so a violation names its own policy in the failure message.
- **Sanity test `repoRootResolves()`** asserts `>100` files scanned (215 today) so a broken repo root fails loudly instead of every rule passing vacuously.
- **Comment lines skipped** — a line whose trimmed content starts with `//` is dead code, not a live violation. This is what lets `FiguresLoadingView.swift`'s doc comment literally say "…replacement for a system `ProgressView()` spinner" without tripping rule 6 (the operator flagged this exact case).
- **Exempt set per rule** — a trailing `/` marks a directory-prefix exemption (rule 7 → `Library/DesignSystem/`, where `AnimationTokens` lives); otherwise it's an exact file path (rule 8 → `AmberTheme.swift`, locking the zero-raw-hex win).
- Failure messages format each hit as `App/Views/Foo.swift:42: <line>`.

Multi-clause rules (3, 5, 7) combine their patterns with a top-level `|` — the `Rule.pattern` stays a single `String` as specced.

## The rules (all clean on main)

| # | Bans | Scope | Exempt |
| -- | -- | -- | -- |
| 1 | `.font(.system(` | App/Library/Widgets | — (`Font.system(` token defs have no `.font(` prefix) |
| 2 | system Dynamic Type styles | App/Library/Widgets | — |
| 3 | `Color.black` / `(.black)` fills | App/Library/Widgets | — |
| 4 | `.foregroundColor(` | App/Library/Widgets | — |
| 5 | `.cornerRadius(` / `cornerRadius: N` | App/Library/Widgets | — |
| 6 | `ProgressView()` | App/Views | — (comment mention skipped) |
| 7 | inline `easeIn/Out/InOut/linear(duration:)` / `spring(response:)` | App/Library/Widgets | `Library/DesignSystem/` |
| 8 | `Color(red:` | App/Library/Widgets | `Library/DesignSystem/AmberTheme.swift` |

**No `deploy.sh` preflight duplicate** — a bash copy of the pattern list would drift from the test. `Cmd+U` / conductr PR checks are the gates.

## Self-test (acceptance)

Planted one scratch file under `App/Views/` with a real, compiling violation of every rule, ran the suite, and confirmed each rule failed naming the planted `file:line`:

- rule 1 → `:13 .font(.system(size: 12))` · rule 2 → `:14 .font(.body)` · rule 3 → `:5 Color.black` **and** `:17 .background(.black)` (both alternation clauses) · rule 4 → `:15 .foregroundColor` · rule 5 → `:16 .cornerRadius(8)` · rule 6 → `:9 ProgressView()` · rule 7 → `:7 easeInOut` **and** `:8 spring` · rule 8 → `:6 Color(red:`

`repoRootResolves()` stayed green throughout. Scratch removed; suite back to green.

## Docs coherence pass

- `design-system.md`: new top-level **## Enforcement** section (rule table, allowlist-extension mechanics, and the sanctioned `.opacity()` exceptions the merge reviews called out — `DOSButtonStyle` pressed-ghost, `AddedEntryHighlighter` animated glow, `WhatsNewView` `dosGlowLarge`, `AddInsulinView` warning wash, `StepperField` washes).
- `CLAUDE.md`: snapshot-testing bullet now lists `StyleGuardTests`; token-consumption flow marked **guard-enforced**.
- Verified every symbol the new docs reference actually exists (`inkOnAmber`, `dosBlack`, the `borderFaint/Subtle/Strong`/`textFaint`/`surfaceTint`/`scrim` tiers, `dosGlowLarge`, `FiguresLoadingView.inline`, `AddedEntryHighlighter`, `AnimationTokens`).

### One accuracy correction

The merge-review note claimed `amberDark.opacity` is "fully eliminated." It isn't quite: `Widgets/GlucoseWidget.swift:516` still fills its "NO CHART DATA" placeholder with `amberDark.opacity(0.1)`, and no pre-blended tier matches `0.1`. Rather than parrot the claim or make an out-of-scope, unreviewed visual change to the widget, I documented the survivor precisely in the Enforcement section ("don't add more"). The guards don't ban `.opacity()`, so this doesn't affect any test — but it's a candidate for a future micro-sweep.

## pbxproj registration

Tests aren't auto-synced. Added 4 entries mirroring `DesignTokenPinTests` with the next ID in sequence (`…002400A00024`): PBXBuildFile, PBXFileReference, `DOSBTSTests` group child, PBXSourcesBuildPhase.

## Verification

- `StyleGuardTests` — 9/9 pass on main ✓
- Self-test: each rule fails on a planted violation naming `file:line`, then green after removal ✓
- Full suite — `** TEST SUCCEEDED **`, 0 failures ✓
- Both targets (`DOSBTSApp`, `DOSBTSWidget`) build clean ✓
- No CHANGELOG entry (tests + dev docs are internal, not user-visible) ✓
