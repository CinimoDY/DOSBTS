# Design System

## Design Philosophy

DOSBTS embraces a nostalgic amber CGA monitor aesthetic reminiscent of DOS-era computing, creating a unique and memorable visual identity that stands apart from typical clinical health app designs.

## Color Palette

### Primary Colors

#### Amber CGA (#FFB000)
- **Usage**: Primary text color, accent elements, highlights
- **Inspiration**: Classic amber CRT monitor glow (authentic CGA amber phosphor)
- **Application**:
  - Main text and labels
  - Data values (glucose readings, carb counts)
  - Interactive elements and buttons
  - Focus states and selections

#### Supporting Colors
- **Background**: `dosBlack` #000000 (pure black)
- **Card Background**: `cardBackground` #1B1917 (warm near-black)
- **Dim amber**: `amberDark` #9a5700 (secondary text, dimmed states — 18pt+ only)
- **Bright amber**: `amberLight` #fdca9f (highlights, focus states)
- **Pressed**: `amberPressed` #cc8c00 (button pressed state)
- **Muted**: `amberMuted` #555555 (disabled states, neutral gray)
- **Success/In-range**: `cgaGreen` #55ff55
- **Error/High**: `cgaRed` #ff5555
- **Info/Cyan**: `cgaCyan` #55ffff

### Color Token Reference (AmberTheme.swift)

| Token | Hex | Usage |
|-------|-----|-------|
| `amber` | #ffb000 | Primary text, data, buttons |
| `amberDark` | #9a5700 | Secondary text, dimmed states (18pt+ only) |
| `amberLight` | #fdca9f | Highlights, focus states |
| `amberPressed` | #cc8c00 | Button pressed state |
| `amberMuted` | #555555 | Disabled states, neutral gray |
| `dosBlack` | #000000 | Primary background |
| `cardBackground` | #1B1917 | Card/section background |
| `dosBorder` | #594F47 | Borders and separators |
| `cgaGreen` | #55ff55 | In-range / success |
| `cgaCyan` | #55ffff | Sensor lines, info, AI insight card |
| `cgaRed` | #ff5555 | Out-of-range / error |
| `cgaMagenta` | #ff55ff | CGA magenta accent |
| `cgaWhite` | #aaaaaa | Neutral/disabled text |
| `iobBolus` | #8CBF40 | IOB meal/snack bolus chart layer |
| `iobBasal` | #5DD0F3 | IOB basal + correction chart layer |

### Usage Guidelines

#### Text Hierarchy
- **Primary Text**: AmberTheme.amber (#ffb000) — informational text, AA-compliant on black
- **Secondary/Dimmed**: AmberTheme.amberDark (#9a5700) — reserved for intentional dimming/disabled/decorative strokes; not for informational text
- **Muted/Disabled**: AmberTheme.amberMuted (#555555) — disabled states, neutral gray

#### Interactive Elements
- **Default State**: Amber text on dark background
- **Pressed**: AmberTheme.amberPressed with 0.97 scale
- **Disabled**: AmberTheme.amberMuted with reduced opacity

## Typography (DOSTypography.swift)

### Font Scale
| Token | Size | Weight | Usage |
|-------|------|--------|-------|
| `glucoseHero` | 60pt | Bold mono + monospacedDigit | Hero glucose display |
| `displayMedium` | 28pt | Bold mono | Section headers |
| `bodyLarge` | 20pt | Regular mono | Emphasized content |
| `body` | 17pt | Regular mono | Standard body text |
| `bodySmall` | 15pt | Regular mono | Secondary body, timestamps, metadata |
| `button` | 17pt | Semibold mono | Interactive elements |
| `caption` | 12pt | Regular mono | Captions, chart axes |
| `tabBar` | 10pt | Medium mono | Navigation labels |
| `mono(size:weight:)` | custom | — | Custom-sized monospaced font |

### Letter Spacing
- **Body**: 0pt (default)
- **Headers**: 1.5pt wide spacing

### View Modifiers
- `.dosText()` — Amber monospace text (no shadow, safe for lists/charts)
- `.dosHeader()` — Header with 1.5pt spacing + phosphor glow
- `.dosData()` — Data display with phosphor glow
- `.dosGlowSmall()` — Subtle CRT phosphor glow shadow
- `.dosGlowLarge()` — Strong phosphor glow shadow

## Spacing (DOSSpacing.swift)

8-step scale: xxs(4), xs(8), sm(12), md(16), lg(24), xl(32), xxl(48), hero(64)

## Visual Effects

### CRT Phosphor Glow
Multi-layer shadows to simulate amber CRT phosphor:
- Inner glow: radius 2, opacity 0.6
- Mid glow: radius 6, opacity 0.3
- Outer glow: radius 12, opacity 0.15

**Performance rule**: No glow shadows inside `Chart{}` body or `ForEach` list rows.

### Contrast & Accessibility
- AmberTheme.amber (#FFB000) on black: ~8.6:1 contrast ratio (WCAG AAA)
- Support for Dynamic Type
- Sharp corners (cornerRadius: 0) for DOS aesthetic

## UI Components

### Buttons (DOSButtonStyle.swift)
- **Primary**: Amber background, black text, 1px border
- **Ghost**: Transparent background, amber text, 1px amber border
- Spring animation on press (0.97 scale)

### Cards (.dosCard() modifier)
- Card background (#1B1917)
- 1px amber-muted border
- DOSSpacing.md padding

### Text Fields (.dosTextField() modifier)
- DOS black background
- Amber text
- 1px amber-muted border

### Navigation
- Tab bar: black background, amber tint, amberDark unselected

### Meal Item (MealItemRow.swift)

One shared component with documented per-context variants (R3). Pixel-identical
rendering across contexts is explicitly not the goal — each variant keeps its
context's layout, but layout rules, type scale, color roles, and affordances
live in one place.

- **`.recent`** — compact single line: `> ` prompt prefix (amberDark), name
  (bodySmall amber, lineLimit 1 + tail truncation), trailing carbs caption.
  Rides inside `HoldToCommitProgress`; must never attach a context menu
  (long-press conflicts with the hold recognizer — DMNC-796 KTD-3). Callers
  pass only `onAddToFavorite`.
- **`.list`** — two-line detail row: timestamp (monospacedDigit) over dimmed
  name caption; trailing carbs + macro captions (P/F/kcal). Attaches leading
  swipe (log again), trailing swipe (delete + favorite), and a context menu
  from whichever callbacks the caller supplies.
- The digest timeline stays flat text (out of scope this wave).

## Component Standard (self-certify checklist)

Every new shared component PR certifies against this list:

- [ ] **Layout**: 8px grid (`DOSSpacing`), cornerRadius 0 (sharp DOS corners, 
      no exceptions), no system-gray grouped surfaces outside exempt chrome.
- [ ] **Type scale**: `DOSTypography` roles only (no ad-hoc font sizes);
      hierarchy carried by size/weight, not by dimming informational text.
- [ ] **Color roles**: `AmberTheme` tokens only. `amber` for informational
      text (AA on black), `amberDark` reserved for intentional dimming /
      disabled / decorative strokes, CGA accents (green/cyan/red) keep their
      semantic meaning. No real white.
- [ ] **Tap targets**: every interactive element ≥44pt; VoiceOver labels
      equivalent to the system control it replaces.
- [ ] **Variants**: per-context variants are documented on the component
      (doc comment) and in this file; affordances are caller-supplied
      callbacks, never baked in.
- [ ] **Display model**: content derivation extracted into a testable,
      equatable model when the mapping is non-trivial (see
      `MealItemDisplayModel`); truncation stays a rendering concern.

## Implementation Notes

### SwiftUI Color Implementation
```swift
// All colors defined in Library/DesignSystem/AmberTheme.swift
// Shared between App and Widget targets
AmberTheme.amber      // Primary amber #ffb000
AmberTheme.dosBlack   // Background #000000
AmberTheme.cgaGreen   // In-range #55ff55
AmberTheme.cgaRed     // Out-of-range #ff5555
```

### File Locations
- `Library/DesignSystem/AmberTheme.swift` — Color tokens (shared)
- `Library/DesignSystem/DOSTypography.swift` — Font tokens + modifiers (shared)
- `Library/DesignSystem/DOSSpacing.swift` — Spacing scale (shared)
- `App/DesignSystem/Components/DOSButtonStyle.swift` — Button style (App only)
- `App/DesignSystem/Modifiers/DOSModifiers.swift` — View modifiers (App only)

### iOS Compatibility
- Deployment target: iOS 26.0

## Prototype-Driven Design Workflow

**Status: provisional** — the full frame→implement→verify loop hasn't been trialed end-to-end yet. The marker is removed once a dense screen is successfully designed in the eiDotter Figma library (DMNC-802) and implemented from the frame without needing prose (U4, DMNC-791).

### When to use a frame vs prose

| Change type | Approach |
|-------------|----------|
| Dense or net-new screen (overview, chart, marker lane, modal) | Figma frame → implement |
| Small/incremental change (button label, toggle position, colour tweak) | Prose description |

When in doubt: if prose would require more than two sentences of spatial description, design a frame.

### The frame→implement→verify loop

1. **Design** — Open the DOSBTS app file in the eiDotter Figma library (DMNC-1119) and design the target frame. Use eiDotter tokens for colour and type; iOS 26 components for system controls.
2. **Hand off** — Provide the Figma frame URL when starting the implementation session. Claude reads the frame live via the Figma MCP (`mcp__claude_ai_Figma__get_design_context`, `get_screenshot`).
3. **Snapshot** — Export the frame as a PNG (optimised via the manual Pillow script — `docs/solutions/best-practices/png-screenshot-optimization-via-pillow-20260422.md`) and commit it plus a companion spec to `docs/design-frames/` in the same PR. See `docs/design-frames/README.md` for naming convention and spec format.
4. **No-MCP fallback** — If the Figma MCP isn't available, implement from the committed snapshot + companion spec in `docs/design-frames/`. The spec must be sufficient on its own (key measurements, tokens, layout notes).
5. **Implement** — Claude implements against the frame/snapshot as the exact design source-of-truth, not prose.
6. **Verify** — Screenshot the running build and compare against the frame. Iterate until the implementation matches.

### Token consumption: mirroring eiDotter into AmberTheme

For each eiDotter token encountered during frame implementation:

- **PORT** — token maps to an existing `AmberTheme` property (use it as-is)
- **SKIP** — token is a system control colour that iOS handles automatically (skip)
- **EVALUATE** — new token not in `AmberTheme`; add it to `AmberTheme.swift`, update `DesignTokenPinTests.swift` expected values, and document it in this file

Never copy raw hex from eiDotter. Always mirror through `AmberTheme` and the drift-guard test.

### Platform constraints checklist

Every frame must be implementable within these iOS/DOSBTS constraints. Flag violations before starting implementation:

- [ ] **Nav titles** — use `dosNavigationTitle` (principal toolbar item), never bare `.navigationTitle` — iOS 26 ignores `UINavigationBar.appearance()` title attributes
- [ ] **Persistent bars** — bottom bars must use `safeAreaInset(edge: .bottom)`, not `tabViewBottomAccessory` (liquid glass conflicts with DOS theme)
- [ ] **Sheets** — no nested sheets; use `NavigationLink` (push) inside a sheet-presented view
- [ ] **No real white** — all text is amber/CGA; `.foregroundStyle(.white)` is forbidden
- [ ] **No ad-hoc font sizes** — use `DOSTypography` members only
- [ ] **NavigationStack** — new screens must use `NavigationStack`, not legacy `NavigationView`

### Token drift-guard

`DOSBTSTests/DesignTokenPinTests.swift` pins the hand-mirrored eiDotter token values. When you add or change a token in `AmberTheme.swift`, update the corresponding expected RGB value in that test. The guard catches accidental local edits; true upstream-divergence detection awaits DMNC-801's generated tokens.

## Brand Identity

### Personality
- Nostalgic and unique
- Technical and precise
- Friendly but not clinical
- Memorable and distinctive

### Differentiation
- Stands out from typical blue/green health app color schemes
- Appeals to users who appreciate retro computing aesthetics
- Creates emotional connection through nostalgia
- Suggests precision and attention to detail

## Motion & Animation

### AnimationTokens (`Library/DesignSystem/AnimationTokens.swift`)

Standard motion tokens used across all animated surfaces.

| Token | Type | Value | Use |
|-------|------|-------|-----|
| `normal` | Spring | response 0.4, damping 0.7 | Card reveals, sheet transitions |
| `snappy` | Spring | response 0.25, damping 0.8 | Interactive feedback, quick state changes |
| `durationShort` | `Double` | 0.15 s | Icon swaps, immediate feedback |
| `durationMedium` | `Double` | 0.25 s | Standard cross-fades |
| `durationLong` | `Double` | 0.4 s | Enter/exit transitions |
| `easeStandard` | Ease | easeInOut 0.25 s | Phase-cycling text, cross-fades |
| `easeExit` | Ease | easeIn 0.15 s | Exit transitions |

#### Reduce-motion adaptation

Use `AnimationTokens.adapted(spring:reduceMotion:)` to degrade a spring to a short linear animation when the user has requested reduced motion. Use `AnimationTokens.adapted(animation:reduceMotion:)` to suppress an animation entirely (`nil`) under reduce-motion.

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

withAnimation(AnimationTokens.adapted(spring: AnimationTokens.normal, reduceMotion: reduceMotion)) {
    // state change
}
```

### FiguresLoadingView (`App/Views/SharedViews/FiguresLoadingView.swift`)

Three pulsing amber dots in the DOS phosphor vocabulary — used on all async-wait surfaces (Claude API analysis, sensor connecting). Built with `TimelineView` + `Canvas` for frame-rate-independent animation.

Under reduce motion, renders three static dots at reduced opacity instead of pulsing.

`cadence` controls the redraw rate: `.smooth` (default) is display-linked for short waits; `.lowPower` redraws ~10×/s for long-lived states like sensor warmup (which can sit in `.transient` for up to ~60 min) so the pulse doesn't run a continuous full-rate render loop.

```swift
FiguresLoadingView()                                   // default: 8pt amber dots, smooth
FiguresLoadingView(dotSize: 10, spacing: 7)            // larger inline variant
FiguresLoadingView(dotSize: 5, spacing: 3, color: AmberTheme.amberLight, cadence: .lowPower)  // subtle, long-lived
```
