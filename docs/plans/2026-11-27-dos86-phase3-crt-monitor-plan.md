# DOS-86 phase 3 — CRT monitor retune (scanlines, glow, vignette) — DMNC-1664

**Goal:** bring DOSBTS's monitor effects to eiDotter DOS-86's "read for hours" values, from one named set of
constants instead of numbers repeated across files. Source: `../dos-86/tokens/dos-86.tokens.json` → `effect.*`
(eiDotter's long-reading preset).

**Branch:** `feat/dos86-crt-monitor` off `main`. **Linear:** DMNC-1664 (parent DMNC-1645).

## Global constraints

- The persisted key stays `showScanlines` / `libre-direct.settings.show-scanlines` (default off). No new state property.
- Don't touch any colour token (`AmberTheme.swift`, `DesignTokenPinTests.swift`): phase 1 (DMNC-1662) is changing those in parallel.
- No glow inside `Chart{}` or `ForEach` list rows (design-system.md performance rule).
- No flicker, no aperture grille. The grille is invisible or causes moiré at 3×. The DOS-86 tokens set flicker to 0 on purpose.
- No Metal shader. SwiftUI `layerEffect` does not render UIKit-backed content (List, TextField, nav bars).
- Effects respect accessibility: the vignette is skipped under Reduce Transparency or Increase Contrast.
  The scanlines stay user-controlled by the toggle.
- Intended differences from DOS-86 (DMNC-1665): pure #000000 screen, bright cyan, SF Mono. Don't touch them.

## Tasks

### 1. Effect constants (new file, auto-synced into both targets)
- [ ] Create `Library/DesignSystem/DOSEffects.swift`:
  ```swift
  /// eiDotter DOS-86 monitor values (`../dos-86/tokens/dos-86.tokens.json` → effect.*, eiDotter's
  /// long-reading preset). Tuned for text read for hours, not a page seen for seconds.
  public enum DOSEffects {
      public enum Scanline {
          /// Peak darkening between raster rows (0–1). DOS-86 effect.scanline.intensity.
          public static let intensity: Double = 0.10
          /// Distance between scanlines in points. DOS-86 effect.scanline.pitch.
          public static let pitch: CGFloat = 3
      }
      public enum Glow {
          /// Tight glow around lit pixels. DOS-86 effect.phosphor.glowRadius / glowIntensity.
          public static let radius: CGFloat = 1.6
          public static let intensity: Double = 0.20
          /// Soft halation further out. DOS-86 effect.phosphor.bloomRadius / bloomIntensity.
          public static let bloomRadius: CGFloat = 4.5
          public static let bloomIntensity: Double = 0.12
      }
      public enum Vignette {
          /// How much dimmer the corners get (0–1). DOS-86 effect.vignette.intensity.
          public static let intensity: Double = 0.22
          /// How far in from the corners the dimming reaches. DOS-86 effect.vignette.spread.
          public static let spread: Double = 0.20
      }
  }
  ```
  `import SwiftUI` (for CGFloat). Keep it free of UIKit: the widget target compiles `Library/`.
- [ ] Pin tests: add a `@Test` group to `DOSBTSTests/AnimationTokensTests.swift` (an existing suite in the target,
  so there's no pbxproj edit). Pin the seven values exactly. **Do not create a new test file.**

### 2. Glow, as two layers
The shader adds glow on top of the lit pixel (`base + glow*0.20 + bloom*0.12`). The closest SwiftUI equivalent is two
same-colour shadows. A SwiftUI shadow at opacity `x` reads dimmer than additive light at intensity `x`, so a literal
port will look much weaker than today. **Tune for the look, not the numbers:** start from the constants, compare
screenshots, and record the multiplier you settle on in `DOSEffects.Glow` with a comment, for example
`/// SwiftUI shadow ≠ additive light; ×N opacity for visual parity with the DOS-86 specimen`.
- [ ] `Library/DesignSystem/DOSTypography.swift:76` `dosGlowLarge` (3 layers today: r1@0.8, r6@0.4, r16@0.15; used on the
  hero glucose `GlucoseView.swift:27,51`, `GlucoseStatusBar.swift:216`, `DigestView.swift:385`, `WhatsNewView.swift:154`)
  → 2 layers from `DOSEffects.Glow`. The hero must still read as glowing at 60pt. Aim for "calmer, tighter", not "gone".
- [ ] `Widgets/WidgetDesignSystem.swift:34` `phosphorGlow` (2 layers: r1@0.8, r4@0.3) → same two-layer source.
  Check it at the widget hero size (44pt) so the glow does not blur the number.
- [ ] `docs/design-system.md` "CRT Phosphor Glow" section (around line 120): replace the 3-layer recipe with the two-layer
  DOS-86 values and a pointer to `DOSEffects`.

### 3. Scanlines with a cosine profile
- [ ] `App/DesignSystem/Components/DOSScanlineOverlay.swift`: replace the 1pt line at 0.04 with the DOS-86 profile.
  For each device-pixel row `y` (read `@Environment(\.displayScale)`; step `1 / displayScale` pt), darkness =
  `intensity * (0.5 - 0.5 * cos(2π * (y mod pitch) / pitch))`. Fill one rect per row with `dosBlack.opacity(darkness)`
  inside the existing `Canvas`. Skip rows where darkness < 0.005. Keep `.ignoresSafeArea()`.
  A `Canvas`-local opacity is a parametric fade, not a fixed dim, so it's sanctioned. If StyleGuard objects anyway,
  follow its documented exemption mechanism rather than weakening the rule.
- [ ] Watch for performance: about 2,600 rows at 3×. Canvas draws them once. Add `.drawingGroup()` if scrolling under the overlay
  shows any hitch in Instruments or by eye.

### 4. Vignette, behind the same toggle
- [ ] New `App/DesignSystem/Components/DOSVignetteOverlay.swift`: an `EllipticalGradient` from `.clear` at
  `startRadiusFraction` ≈ `0.5 - spread` … to `dosBlack.opacity(intensity)` at `1.0`. Tune it so the dimming only reaches the
  outer edge and corners, and never the hero glucose value or the bottom-bar buttons' text enough to change their contrast.
  `.allowsHitTesting(false)`, `.ignoresSafeArea()`, and `accessibilityHidden(true)`.
  Return `EmptyView` when `@Environment(\.accessibilityReduceTransparency)` is true or `colorSchemeContrast == .increased`.
- [ ] `App/Views/ContentView.swift:64-69`: mount it in the same `if store.state.showScanlines` overlay, next to `DOSScanlineOverlay`.
- [ ] `App/Views/Settings/GlucoseDisplayCategoryView.swift:71`: rename the toggle label from "CRT scanline overlay" to
  "CRT monitor effect" (the key does not change). Add a one-line caption under it, styled like the "Keep screen awake"
  caption right below (`DOSTypography.caption`, `AmberTheme.amber`): "Scanlines and a soft edge vignette, tuned for long reading."

### 5. Changelog
- [ ] `CHANGELOG.md` → `## [Unreleased]` → `### Changed`:
  `- The CRT monitor effect (Settings → Glucose & Display, now called "CRT monitor effect") has softer, more even scanlines and a faint edge vignette, and the phosphor glow on the big glucose number is tighter and calmer — tuned for long reading after the eiDotter DOS-86 theme — DMNC-1664, PR #NN`

## Verification
- [ ] Build both schemes (DOSBTSApp, DOSBTSWidget) on your assigned simulator UDID. Redirect logs to a file and grep for `** BUILD SUCCEEDED **`.
- [ ] Tests: `-only-testing:DOSBTSTests/AnimationTokensTests -only-testing:DOSBTSTests/StyleGuardTests` (`@Suite` type names; confirm that
  the test count is > 0), then the full `DOSBTSTests` suite once.
- [ ] Screenshots before (on `main`) and after, with the toggle ON and OFF: Overview (hero glow), Settings › Glucose & Display (new label),
  and a widget preview if one is reachable. Save them under `$SCRATCH/dos86-phase3/` and list the paths in the PR body. The glow
  multiplier you chose and why go in the PR body. Dom judges the final look on device.

## Ship
- [ ] Commit this plan file too (`docs/plans/2026-11-27-dos86-phase3-crt-monitor-plan.md`).
- [ ] Move the `IMPLEMENTATION_NOTES.md` content into the PR body, then `git rm` the file.
- [ ] PR title: `feat(design): DOS-86 long-reading CRT monitor — scanlines, glow, vignette (DMNC-1664)`.
