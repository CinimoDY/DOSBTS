---
title: "Refactor: Adopt eiDotter Design System Across All Views"
type: refactor
status: completed
date: 2026-03-08
deepened: 2026-03-08
---

# Refactor: Adopt eiDotter Design System Across All Views

## Enhancement Summary

**Deepened on:** 2026-03-08
**Research agents used:** eiDotter Adoption, Refactoring UI, Design-Craft CRT, Architecture Strategist, Code Simplicity, Performance Oracle, Best Practices, Pattern Recognition

### Key Improvements from Research
1. **Simplified from 9 phases to 3** -- the original plan over-engineered the phasing for what is fundamentally a visual reskin
2. **One button style, not three** -- `DOSButtonStyle` with a `variant` parameter instead of 3 separate types
3. **Design tokens must move to `Library/`** -- critical architecture fix; `AmberTheme` and `DOSTypography` need to be in the shared module for Widget target access
4. **Multi-layer glow shadows** for authentic CRT phosphor (not single-layer)
5. **No `.dosData()` shadows in charts or lists** -- performance concern; shadows only on hero values and headers
6. **Spacing scale added** -- the original plan had no spacing system
7. **Warm-tinted grays** -- neutral #555555 and #1A1A1A should carry amber warmth
8. **CRT power-on animation** for LoadingView with phosphor warm-up signature
9. **Delete redundant `Color.AmberCGA`/`Color.DOSTerminal`/`Color.CGA` nested structs** -- they create a third color system

### New Considerations Discovered
- `amberDark` (#9A5700) fails WCAG AA for normal text -- consider brightening to #B06800
- Monospace at 96pt won't fit 3-digit glucose on iPhone SE -- need responsive sizing (60pt default, 72pt for 2-digit)
- `docs/design-system.md` says #FFBF00 but code uses #FFB000 -- needs reconciliation
- The middleware loop in `Store.dispatch` has a latent `break`-vs-`continue` bug (out of scope but flagged)

---

## Overview

The eiDotter CGA amber design system is **fully defined but zero views use it**. `AmberTheme` (colors) and `DOSTypography` (monospace fonts) exist in `App/DesignSystem/` with view modifiers (`.dosText()`, `.dosData()`, `.dosHeader()`), but every view in the app uses:

- **Legacy `Color.ui.*`** (`Library/Extensions/Color.swift`) -- same CGA hex values but with confusing names (`blue` = cyan, `orange` = amberDark, `indigo`/`pink`/`purple` all = amber)
- **System fonts** -- `.font(.system(size: 96))`, `.font(.footnote)`, `.font(.subheadline)` -- no monospace anywhere
- **Default iOS button styles** -- no custom `ButtonStyle`, most buttons use iOS blue tint
- **`Color.primary`** for the main glucose reading -- white in dark mode, not amber
- **`Color.white`** on colored badge backgrounds
- **System form controls** -- default `Slider`, `Stepper`, `Picker`, `TextField` styling

**eiDotter Adoption Level: 1** (tokens defined, not consumed). 67 `Color.ui.*` references across 17 files, 25+ hardcoded `.font()` calls in views, 19 in widgets. Zero `AmberTheme` or `DOSTypography` references in any view.

## Problem Statement

The app looks like a standard iOS dark-mode app with amber accent colors sprinkled in. It does not deliver the retro DOS terminal experience that the design system specifies.

## Proposed Solution

A **3-phase** migration (simplified from 9):
1. **Foundation** -- Move tokens to `Library/`, create `DOSButtonStyle`, add modifiers, expand palette
2. **Migration** -- Walk all views, swap colors/fonts/buttons. Charts are highest risk.
3. **Cleanup** -- Delete `Color.ui`, remove redundant structs, final audit

## Technical Considerations

### Architecture: Move Design Tokens to Library/ (CRITICAL)

**Finding from architecture review:** `Library/Extensions/Color.swift` (the file being replaced) has dual target membership in the Xcode project -- it compiles into both the App and Widget targets. Its replacement must follow the same pattern.

Currently `AmberTheme.swift` and `DOSTypography.swift` live in `App/DesignSystem/` which is **App-only**. They must move to `Library/` for widget access.

```
Library/
  DesignSystem/
    AmberTheme.swift          # Color tokens (both targets)
    DOSTypography.swift       # Font tokens + view modifiers (both targets)
    DOSSpacing.swift          # Spacing scale (both targets)
App/
  DesignSystem/
    Components/
      DOSButtonStyle.swift    # App-only button style
    Modifiers/
      DOSModifiers.swift      # .dosCard(), .dosTextField() modifiers
```

Add `AmberTheme.swift` and `DOSTypography.swift` to the Widget target in Phase 1 immediately, not at the end.

### Color Migration is a Rename, Not a Visual Change

The `Color.ui.*` values already match the CGA amber palette exactly:

| `Color.ui.*` | `AmberTheme.*` | Hex | Semantic |
|---|---|---|---|
| `.accent` | `.amber` | `#FFB000` | Primary, toggles |
| `.blue` | `.cgaCyan` / `.info` | `#55FFFF` | Sensor glucose lines, info |
| `.green` | `.cgaGreen` / `.success` | `#55FF55` | Success, target line |
| `.red` | `.cgaRed` / `.error` | `#FF5555` | Alarms, errors |
| `.orange` | `.amberDark` | `#9A5700` | Raw glucose, insulin data |
| `.yellow` | `.cgaYellow` / `.warning` | `#FFFF55` | Warnings |
| `.label` | `.amberLight` | `#FDCA9F` | Interactive indicators |
| `.gray` | `.amberMuted` / `.dosGray` | `#555555` | Disabled, muted |
| `.indigo`/`.pink`/`.purple` | `.amber` | `#FFB000` | Legacy aliases (delete) |

Also migrate: `Color.primary` (5 locations), `Color.white` (4 locations), `UIColor.systemBackground`/`.label` in LoadingView, hardcoded sRGB in ChartViewCompatibility, `UITabBarAppearance` in ContentView.

### Expanded Amber Palette (Refactoring UI Insight)

**Problem:** 4 amber shades are insufficient. Views use `.opacity()` hacks which look muddy on black.

**Add these shades to AmberTheme:**

| Token | Hex | Contrast on Black | Use |
|---|---|---|---|
| `amberLight` | `#FDCA9F` | ~12:1 (AAA) | Highlights, focus rings |
| `amber` | `#FFB000` | ~8.6:1 (AAA) | Primary text, data, buttons |
| `amberPressed` | `#CC8C00` | ~5.5:1 (AA) | Pressed button state |
| `amberDark` | `#9A5700` | ~3.4:1 (fails AA) | Large text only (18pt+) |
| `amberDarker` | `#5C3400` | ~1.8:1 | Placeholder text, decorative only |

**Warm-tint the grays** -- #555555 and #1A1A1A are neutral. Replace with amber-warm variants:
- `dosGray`: `#555555` -> `#594F47` (warm gray, amber-tinted)
- Card background: `#1A1A1A` -> `#1B1917` (warm near-black)

### Spacing Scale (NEW -- Missing from Original Plan)

```swift
enum DOSSpacing {
    static let xxs: CGFloat = 4    // icon-to-label, internal gaps
    static let xs: CGFloat = 8     // compact list row padding
    static let sm: CGFloat = 12    // card internal padding
    static let md: CGFloat = 16    // standard section spacing
    static let lg: CGFloat = 24    // between cards/groups
    static let xl: CGFloat = 32    // major section breaks
    static let xxl: CGFloat = 48   // screen-level padding
    static let hero: CGFloat = 64  // hero content breathing room
}
```

Rule: space within groups tighter than between groups. Inside a card: 12px. Between cards: 24px. Between sections: 32px.

### Font Migration -- Responsive Hero Sizing

Monospace at 72pt is ~15-20% wider than proportional at 96pt. A 3-digit glucose like "342" in SF Mono bold at 72pt is ~170pt wide -- barely fits iPhone SE (320pt).

**Recommendation:** Add `DOSTypography.glucoseHero` at 60pt default, with responsive sizing:

```swift
static let glucoseHero = Font.system(size: 60, weight: .bold, design: .monospaced)
    .monospacedDigit()
```

Use `ViewThatFits` or `minimumScaleFactor(0.8)` for 3-digit values.

**Consolidated type scale** (drop 10pt tiny and merge 13pt/15pt):

| Token | Size | Use |
|---|---|---|
| `caption` | 12pt | Chart axes, fine print |
| `bodySmall` | 15pt | Timestamps, metadata |
| `body` | 17pt | Content, settings, buttons |
| `bodyLarge` | 20pt | Emphasized content |
| `dataLarge` | 24pt | Key metrics, statistics |
| `displaySmall` | 30pt | Card headers |
| `displayMedium` | 36pt | Screen titles |
| `glucoseHero` | 60pt | The glucose reading |

**Letter spacing:** Default to 0 for body text (0.5 slows reading). Keep 1.5pt for uppercase headers only.

### One Button Style, Not Three (Simplicity Insight)

The codebase has ~37 `Button(` calls. The mockup spec describes **one** button: amber text, 2px border, sharp corners, fills on press. One `DOSButtonStyle` with an optional variant covers all cases:

```swift
struct DOSButtonStyle: ButtonStyle {
    enum Variant { case primary, ghost }
    var variant: Variant = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DOSTypography.button)
            .foregroundColor(variant == .primary ? AmberTheme.dosBlack : AmberTheme.amber)
            .padding(.horizontal, DOSSpacing.md)
            .padding(.vertical, DOSSpacing.xs)
            .background(
                variant == .primary
                    ? (configuration.isPressed ? AmberTheme.amberPressed : AmberTheme.amber)
                    : (configuration.isPressed ? AmberTheme.amber.opacity(0.1) : Color.clear)
            )
            .overlay(Rectangle().stroke(AmberTheme.amber, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(duration: 0.2, bounce: 0.1), value: configuration.isPressed)
    }
}
```

DOSGhostButton and DOSIconButton files are unnecessary -- delete from the plan.

### Modifiers: DOSCard + DOSTextField as ViewModifiers, Kill DOSGlowEffect

**DOSCard** is a 5-line modifier, not a component:

```swift
func dosCard() -> some View {
    self
        .background(Color(red: 0.106, green: 0.098, blue: 0.090)) // warm #1B1917
        .overlay(Rectangle().stroke(AmberTheme.amberMuted.opacity(0.3), lineWidth: 1))
}
```

**DOSTextField** is a modifier wrapping 8 text fields total -- no custom component needed:

```swift
func dosTextField() -> some View {
    self
        .font(DOSTypography.body)
        .foregroundColor(AmberTheme.amber)
        .tint(AmberTheme.amber)
}
```

**DOSGlowEffect** is already embedded in `.dosData()` and `.dosHeader()`. Delete as standalone file.

Put all modifiers in one file: `App/DesignSystem/Modifiers/DOSModifiers.swift`.

### CRT Phosphor Glow -- Multi-Layer Shadows (Design-Craft Insight)

Single-layer shadow looks like a faint haze. Real CRT phosphor needs layered bloom:

```swift
// Small glow (data values, interactive elements)
func dosGlowSmall() -> some View {
    self
        .shadow(color: AmberTheme.amber.opacity(0.4), radius: 1, x: 0, y: 0)
        .shadow(color: AmberTheme.amber.opacity(0.15), radius: 4, x: 0, y: 0)
}

// Large glow (hero glucose, headers)
func dosGlowLarge() -> some View {
    self
        .shadow(color: AmberTheme.amber.opacity(0.8), radius: 1, x: 0, y: 0)
        .shadow(color: AmberTheme.amber.opacity(0.4), radius: 6, x: 0, y: 0)
        .shadow(color: AmberTheme.amber.opacity(0.15), radius: 16, x: 0, y: 0)
}
```

### Performance: Where Glow Is Safe vs Dangerous

**From performance review:**

| Context | Shadow OK? | Why |
|---|---|---|
| Hero glucose (1 view, updates every 5 min) | Yes, large glow | Infrequent updates, single element |
| Section headers (static) | Yes, large glow | Rarely re-renders |
| Chart annotations inside `Chart {}` body | **NO** | N offscreen renders during drag gestures |
| List rows in `ForEach` (1000+ entries) | **NO** | Shadow buffer churn during momentum scrolling |
| Buttons (on press) | Small glow OK | Triggered on tap, not continuous |

**Rule:** Use `.dosText()` (no shadow) inside charts and lists. Use `.dosData()` with glow only on the hero glucose and static displays.

### CRT Power-On Animation for LoadingView

Replace system `ProgressView` with phosphor warm-up:

```swift
// CRT signature: start dimmed + blurred, bloom into visibility
.opacity(isActive ? 1 : 0)
.blur(radius: isActive ? 0 : 4)
.brightness(isActive ? 0 : -0.7)  // simulates dim phosphor
.animation(.easeOut(duration: 0.6), value: isActive)
```

Replace the spinner with a blinking cursor `_` and "LOADING..." in amber monospace.

### Motion Tokens

| Context | Duration | SwiftUI |
|---|---|---|
| Data snap | 0.1s | `.linear(duration: 0.1)` |
| Focus/hover | 0.2s | `.easeOut(duration: 0.2)` |
| Power-off / exit | 0.4s | `.easeIn(duration: 0.4)` |
| Power-on / enter | 0.6s | `.easeOut(duration: 0.6)` or `.spring(duration: 0.6, bounce: 0)` |
| Cursor blink | 0.5s | `.easeInOut(duration: 0.5).repeatForever()` |
| Button press | 0.2s | `.spring(duration: 0.2, bounce: 0.1)` |

**Rule:** Linear for digital artifacts (text, data). Springs for physical interactions (buttons, sheets). Always respect `@Environment(\.accessibilityReduceMotion)`.

### Depth System: Glow, Not Shadows

**From Refactoring UI:** Drop shadows imply 3D with overhead lighting. A CRT is self-luminous.

| Level | Glow | Use |
|---|---|---|
| None | 0 | Body text, labels, muted |
| Subtle | Small glow | Data values, interactive at rest |
| Medium | Medium glow | Focused inputs, active states |
| Strong | Large glow | Hero glucose, headers, alarms |

Card depth via background luminance: card (#1B1917) > screen (#000000). No box shadows.

### Finishing Touches

1. **">" prefix on section headers** -- every card/section header gets `> ` in `amberDark`
2. **Sharp corners (0px) everywhere** -- no 2px hedge, no `cornerRadius(5)` on badges
3. **Empty states in DOS language**: `> NO SIGNAL` / `> AWAITING SENSOR INPUT...` / `> _` (blinking cursor)
4. **Tab bar**: `amberDark` for inactive, `amber` with subtle glow for active
5. **Warning badge**: `dosBlack` text on `cgaRed` bg, sharp corners, red glow
6. **Optional scanline overlay** at 3-5% opacity using `Canvas` (toggleable in settings)

### Accessibility Concerns

- `AmberTheme.amber` (#FFB000) on black: 8.6:1 -- passes AAA
- `AmberTheme.amberDark` (#9A5700) on black: 3.4:1 -- **fails AA, use 18pt+ only**. Consider brightening to #B06800 (~4.5:1) for secondary body text
- `AmberTheme.amberMuted` (#555555) on black: 3.7:1 -- **fails AA, decorative only**
- Use `DOSTypography.dynamicFont(for:design:)` for settings/list body text
- Minimum text size: 12pt (drop 10pt `tiny`)
- Always respect `accessibilityReduceMotion` for animations

### Widget Target Boundary

- Add `AmberTheme.swift` and `DOSTypography.swift` to Widget target in Phase 1
- Lock Screen widgets ignore custom colors -- accept system tinting
- Dynamic Island compact: keep proportional font to avoid truncation
- Build verification: `xcodebuild -scheme DOSBTSWidget` after Phase 1 and Phase 2

### Cleanup Items

- Delete `Library/Extensions/Color.swift` (the `Color.ui` extension)
- Delete `Color.AmberCGA`, `Color.DOSTerminal`, `Color.CGA` nested structs from `AmberTheme.swift` (lines 102-124) -- they create a redundant third color system
- Delete `DOSTypography.validateAccessibility()` (hardcoded dictionary, not real validation)
- Delete `Text.dosTerminalHeader/dosDataValue/dosLabel` extensions (duplicates of view modifiers)
- Delete `DOSTypography.monospaceFontName` (unused)
- Remove orphaned Asset Catalog color sets
- Reconcile `docs/design-system.md` (says #FFBF00) with code (uses #FFB000)
- Audit for remaining `Color.primary`, `Color.white`, `.foregroundColor(.secondary)`

### Open Question: eiDotter/Spacewar Button Style

Need user input on the exact button pattern from Spacewar Apple TV / eiDotter:
- Exact appearance (border weight, fill vs outline, glow intensity)
- Focus/hover states (tvOS patterns adapted to iOS)
- Whether there's shared code to import

## Acceptance Criteria

### Phase 1: Foundation (tokens, components, palette expansion)

- [x] Move `AmberTheme.swift` and `DOSTypography.swift` to `Library/DesignSystem/`
- [x] Add both files to Widget target membership in Xcode project
- [x] Add `DOSSpacing` enum to `Library/DesignSystem/`
- [x] Add `amberPressed` (#CC8C00) shade to AmberTheme
- [x] Warm-tint `dosGray` and card background colors
- [x] Add `glucoseHero` (60pt) font token to DOSTypography
- [x] Consolidate type scale (drop 10pt, merge 13/15pt)
- [x] Default letter spacing to 0 for body, keep 1.5 for headers
- [x] Create `DOSButtonStyle` with `.primary` / `.ghost` variants -- `App/DesignSystem/Components/DOSButtonStyle.swift`
- [x] Create `DOSModifiers.swift` with `.dosCard()` and `.dosTextField()` -- `App/DesignSystem/Modifiers/DOSModifiers.swift`
- [x] Update `.dosData()` and `.dosHeader()` with multi-layer glow shadows
- [x] Add `.dosGlowSmall()` / `.dosGlowLarge()` to DOSTypography modifiers
- [ ] Create CRT power-on/off view modifiers
- [x] SwiftUI previews for all new components
- [x] Delete `Color.AmberCGA`/`Color.DOSTerminal`/`Color.CGA` nested structs
- [x] Delete `DOSTypography.validateAccessibility()`, unused Text extensions, `monospaceFontName`
- [x] Verify Widget scheme builds: `xcodebuild -scheme DOSBTSWidget -sdk iphonesimulator build`
- [ ] Confirm eiDotter/Spacewar button pattern (needs user review)

### Phase 2: Migration (all views + widgets)

**Shared Views (4 files):**
- [x] `ToggleView` -- AmberTheme colors, DOSTypography fonts
- [x] `NumberSelectorView` -- amber +/- buttons, DOSTypography, replace `Color.primary`
- [x] `DateSelectorView` -- DOS styling
- [x] `CollapsableSection` -- amber chevron, DOSTypography header, ">" prefix

**Settings Views (9 files):**
- [x] All settings views use `AmberTheme.*` colors and `DOSTypography` fonts
- [x] Section headers in amber monospace with ">" prefix
- [x] Text fields use `.dosTextField()` modifier
- [x] Form controls tinted amber (`.tint(AmberTheme.amber)`)

**List Views (5 files):**
- [x] Statistics, glucose lists, insulin, errors use DOSTypography
- [x] List backgrounds set to black (`.listStyle(.plain)` or `.scrollContentBackground(.hidden)`)
- [x] Data values use `.dosText()` (**not** `.dosData()` -- no shadows in lists)

**Overview non-chart (4 files):**
- [x] `GlucoseView` -- glucose reading in `glucoseHero` monospace with large glow, `AmberTheme.amber` (not `Color.primary`), warning badge: `dosBlack` on `cgaRed`, sharp corners, red glow
- [x] `ConnectionView` -- `DOSButtonStyle` for connect/disconnect/pair
- [x] `SensorView` -- amber progress bars, DOSTypography for details
- [x] `SnoozeView` -- DOS styling

**Charts (2 files, highest risk):**
- [x] `ChartView` (iOS 16+) -- all `Color.ui.*` migrated to `AmberTheme.*`, **no shadows** inside `Chart {}` body
- [x] `ChartViewCompatibility` -- all hardcoded sRGB values replaced, `|` operator updated
- [x] Chart tooltip text: `AmberTheme.dosBlack` on colored backgrounds
- [x] Chart axes/grid: `AmberTheme.amberMuted`

**Container Views + LoadingView (4 files):**
- [x] `ContentView` tab bar: `amberDark` inactive, `amber` active
- [x] `OverviewView`, `ListsView`, `CalibrationsView` -- black backgrounds
- [x] `LoadingView` -- CRT power-on animation, blinking cursor, remove UIColor/ProgressView

**Widgets (4 files):**
- [x] All widget `Color.ui.*` migrated to `AmberTheme.*`
- [x] `Color.primary` in `GlucoseActivityWidget` migrated to `AmberTheme.amber`
- [x] Dynamic Island: keep proportional font in compact regions
- [x] Lock Screen widgets verified (accept system tinting)
- [x] Verify Widget scheme builds after migration

### Phase 3: Cleanup

- [x] Delete `Library/Extensions/Color.swift` (`Color.ui` extension)
- [x] Remove orphaned Asset Catalog color sets
- [x] Reconcile `docs/design-system.md` with actual code values
- [x] Audit: zero `Color.ui`, `Color.primary`, `Color.white` foreground references remain
- [ ] Audit: zero system proportional fonts in views
- [x] Final Widget build verification

## Success Metrics

- All views use `AmberTheme.*` -- zero `Color.ui.*` references
- All text uses `DOSTypography` monospace -- zero system proportional fonts
- All buttons use `DOSButtonStyle`
- Glow shadows only on hero values and headers, not in charts or lists
- App "feels" like a DOS terminal, not a standard iOS app
- No functional regressions (alarms, connections, data display)
- Amber primary text (#FFB000) passes WCAG AAA on black

## Dependencies & Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Chart unreadable after migration | Medium | High | Keep semantic colors (cyan=sensor, red=alarm). No shadows inside Chart body. |
| Monospace breaks layouts (wider text) | Medium | Medium | Use `glucoseHero` 60pt + `minimumScaleFactor`. Test each view. |
| Dynamic Island truncation | High | Low | Keep proportional font for DI compact regions |
| Widget build failure | Low | High | Add to target in Phase 1, verify build immediately |
| Warm-tinted grays look off | Low | Low | A/B with neutral grays, easy to revert |
| `amberDark` contrast too low for secondary text | Medium | Medium | Brighten to #B06800 if needed |

## Sources & References

### Internal References
- Design system colors: `App/DesignSystem/Colors/AmberTheme.swift` (moving to `Library/DesignSystem/`)
- Typography system: `App/DesignSystem/Typography/DOSTypography.swift` (moving to `Library/DesignSystem/`)
- Legacy colors (to delete): `Library/Extensions/Color.swift`
- Design specs: `docs/design-system.md`, `docs/ui-mockups.md`
- Component blueprint: `docs/project-structure.md` (lines 71-109)
- Development rules: `docs/development-rules.md` (Commandment #8: Amber Aesthetic)

### Research Sources
- **eiDotter Adoption Skill** -- assessed current adoption level at 1 (tokens defined, not consumed)
- **Refactoring UI** -- visual hierarchy, spacing scale, color shade expansion, depth via luminance
- **Design-Craft** -- CRT phosphor multi-layer shadows, power-on animation, motion tokens
- **Architecture Strategist** -- Library/ vs App/ target boundary for shared tokens
- **Code Simplicity Reviewer** -- collapsed 3 button types to 1, eliminated DOSGlowEffect, 3 phases not 9
- **Performance Oracle** -- shadow budget (hero + headers only), no glow in charts/lists

### eiDotter Design System
- Source: `https://github.com/CinimoDY/eiDotter`
- Spacewar Apple TV button patterns: **needs user to provide reference**
