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
- **Background**: DOS black (#0A0A0A)
- **Card Background**: Warm near-black (#1B1917)
- **Secondary Text / Amber Dark**: #CC8C00
- **Amber Light**: #FFD580
- **Amber Muted**: Warm gray (#594F47)
- **Success**: CGA Green (#00AA00)
- **Warning/Alert**: CGA Red (#AA0000)
- **Info**: CGA Cyan (#00AAAA)

### Color Token Reference (AmberTheme.swift)

| Token | Hex | Usage |
|-------|-----|-------|
| `amber` | #FFB000 | Primary text, data, buttons |
| `amberDark` | #CC8C00 | Secondary text, dimmed states |
| `amberLight` | #FFD580 | Highlights, emphasis |
| `amberMuted` | #594F47 | Borders, grid lines, disabled text |
| `amberPressed` | #CC8C00 | Button pressed state |
| `dosBlack` | #0A0A0A | Primary background |
| `cardBackground` | #1B1917 | Card/section background |
| `dosGray` | #594F47 | Warm-tinted gray, separators |
| `dosBorder` | #594F47 | Borders |
| `cgaGreen` | #00AA00 | In-range / success |
| `cgaRed` | #AA0000 | Out-of-range / error |
| `cgaCyan` | #00AAAA | Sensor data lines, info |
| `cgaWhite` | #AAAAAA | Neutral text |

### Usage Guidelines

#### Text Hierarchy
- **Primary Text**: AmberTheme.amber (#FFB000)
- **Secondary Text**: AmberTheme.amberDark (#CC8C00)
- **Muted/Disabled**: AmberTheme.amberMuted (#594F47)

#### Interactive Elements
- **Default State**: Amber text on dark background
- **Pressed**: AmberTheme.amberPressed with 0.97 scale
- **Disabled**: AmberTheme.amberMuted with reduced opacity

## Typography (DOSTypography.swift)

### Font Scale
| Token | Size | Weight | Usage |
|-------|------|--------|-------|
| `glucoseHero` | 60pt | Bold mono | Hero glucose display |
| `title` | 28pt | Bold mono | Screen titles |
| `header` | 22pt | Bold mono | Section headers |
| `body` | 17pt | Regular mono | Body text |
| `bodySmall` | 15pt | Regular mono | Secondary body |
| `button` | 15pt | Medium mono | Button labels |
| `caption` | 13pt | Regular mono | Captions, labels |
| `data` | 17pt | Medium mono | Data values |

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

## Implementation Notes

### SwiftUI Color Implementation
```swift
// All colors defined in Library/DesignSystem/AmberTheme.swift
// Shared between App and Widget targets
AmberTheme.amber      // Primary amber #FFB000
AmberTheme.dosBlack   // Background #0A0A0A
AmberTheme.cgaGreen   // In-range #00AA00
AmberTheme.cgaRed     // Out-of-range #AA0000
```

### File Locations
- `Library/DesignSystem/AmberTheme.swift` — Color tokens (shared)
- `Library/DesignSystem/DOSTypography.swift` — Font tokens + modifiers (shared)
- `Library/DesignSystem/DOSSpacing.swift` — Spacing scale (shared)
- `App/DesignSystem/Components/DOSButtonStyle.swift` — Button style (App only)
- `App/DesignSystem/Modifiers/DOSModifiers.swift` — View modifiers (App only)

### iOS Compatibility
- Deployment target: iOS 15.0
- No `.kerning()` on View (iOS 16+ only)
- Use `.tracking()` on Text if needed

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
