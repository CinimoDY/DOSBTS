//
//  AmberTheme.swift
//  DOSBTS
//
//  eiDotter CGA Amber Design System - iOS Token Mapping
//  Source: https://github.com/CinimoDY/eiDotter
//

import SwiftUI

/// eiDotter CGA Amber Theme - Token-aligned color definitions
public enum AmberTheme {

    // MARK: - Primary Amber Colors (eiDotter tokens)

    /// --color-cga-amber: #ffb000 - P3 phosphor amber (602nm)
    public static let amber = Color(red: 1.0, green: 176.0 / 255.0, blue: 0)

    /// --color-cga-amber-dim: #9a5700 - Secondary text, dimmed states (18pt+ only)
    public static let amberDark = Color(red: 154.0 / 255.0, green: 87.0 / 255.0, blue: 0)

    /// --color-cga-amber-bright: #fdca9f - Highlights, focus states
    public static let amberLight = Color(red: 253.0 / 255.0, green: 202.0 / 255.0, blue: 159.0 / 255.0)

    /// Pressed button state: #CC8C00
    public static let amberPressed = Color(red: 204.0 / 255.0, green: 140.0 / 255.0, blue: 0)

    /// --color-cga-dark-gray: #555555 - Disabled states, muted
    public static let amberMuted = Color(red: 85.0 / 255.0, green: 85.0 / 255.0, blue: 85.0 / 255.0)

    // MARK: - CGA 16-Color Palette (eiDotter tokens)

    /// --color-cga-bright-green: #55ff55
    public static let cgaGreen = Color(red: 85.0 / 255.0, green: 1.0, blue: 85.0 / 255.0)

    /// --color-cga-bright-cyan: #55ffff
    public static let cgaCyan = Color(red: 85.0 / 255.0, green: 1.0, blue: 1.0)

    /// --color-cga-bright-red: #ff5555
    public static let cgaRed = Color(red: 1.0, green: 85.0 / 255.0, blue: 85.0 / 255.0)

    /// --color-cga-bright-magenta: #ff55ff
    public static let cgaMagenta = Color(red: 1.0, green: 85.0 / 255.0, blue: 1.0)

    /// --color-cga-white: #aaaaaa
    public static let cgaWhite = Color(red: 170.0 / 255.0, green: 170.0 / 255.0, blue: 170.0 / 255.0)

    // MARK: - DOS Terminal Background Colors

    /// --color-cga-black: #000000
    public static let dosBlack = Color(red: 0, green: 0, blue: 0)

    /// Warm dark gray for borders and separators: #594F47
    public static let dosBorder = Color(red: 89.0 / 255.0, green: 79.0 / 255.0, blue: 71.0 / 255.0)

    /// Warm near-black for card backgrounds: #1B1917
    public static let cardBackground = Color(red: 27.0 / 255.0, green: 25.0 / 255.0, blue: 23.0 / 255.0)

    // MARK: - Semantic tiers (pre-blended; never write .opacity() on palette tokens in views)

    /// Faintest structure: grid lines, separators (was amberDark @ 0.3)
    public static let borderFaint = amberDark.opacity(0.3)
    /// Quiet card hairlines: stat cells, dividers (was amberDark @ 0.4–0.5)
    public static let borderSubtle = amberDark.opacity(0.4)
    /// Emphasized dim stroke (was amberDark @ 0.6)
    public static let borderStrong = amberDark.opacity(0.6)
    /// Helper text a step below amberDark (was amberDark @ 0.7)
    public static let textFaint = amberDark.opacity(0.7)
    /// Faint amber wash behind stat cells (was amber @ 0.04)
    public static let surfaceTint = amber.opacity(0.04)
    /// Modal/overlay dimming (rationalizes ad-hoc black 0.5–0.8)
    public static let scrim = dosBlack.opacity(0.7)
    /// Near-opaque toast backdrop (rationalizes black 0.9–0.95)
    public static let scrimHeavy = dosBlack.opacity(0.95)
    /// Ink on solid amber fills — selected chips, primary buttons.
    /// Same value as dosBlack; the NAME is the intent (survives the AmberTheme.dosBlack guard).
    public static let inkOnAmber = dosBlack

    // MARK: - IOB component colors (split-IOB chart layers)

    /// Warm green (yellow-leaning) for meal/snack bolus IOB: ~#8CBF40.
    /// Distinct from `iobBasal` so split-IOB layers read as related-but-different greens
    /// without needing a legend.
    public static let iobBolus = Color(red: 140.0 / 255.0, green: 191.0 / 255.0, blue: 64.0 / 255.0)

    /// Bright sky-blue for basal + correction IOB: ~#5DD0F3. Distinct from
    /// the warm-green `iobBolus` so the two layers in the split-IOB stack
    /// are unambiguous. Avoids cgaCyan (used by the dim exercise band) and
    /// cgaMagenta (used by the HR overlay).
    public static let iobBasal = Color(red: 93.0 / 255.0, green: 208.0 / 255.0, blue: 243.0 / 255.0)

    // MARK: - Glucose Color Functions

    /// Raw RGB tuples for interpolation (avoids UIKit dependency)
    private static let greenRGB = (r: 85.0 / 255.0, g: 1.0, b: 85.0 / 255.0)
    private static let amberRGB = (r: 1.0, g: 176.0 / 255.0, b: 0.0)
    private static let redRGB = (r: 1.0, g: 85.0 / 255.0, b: 85.0 / 255.0)

    // MARK: - Chart Transition Colors (pre-computed blends)

    /// Red→Green at 30% — exiting danger zone
    public static let glucoseLowBuffer = interpolateRGB(from: redRGB, to: greenRGB, t: 0.3)
    /// Green→Amber at 40% — starting to rise
    public static let glucoseRising = interpolateRGB(from: greenRGB, to: amberRGB, t: 0.4)
    /// Amber→Red at 50% — entering danger above
    public static let glucoseHighBuffer = interpolateRGB(from: amberRGB, to: redRGB, t: 0.5)

    /// Gradient glucose color based on mg/dL value
    public static func glucoseColor(forValue value: Int, low: Int, high: Int) -> Color {
        let v = Double(value)
        let lo = Double(low)
        let hi = Double(high)
        let perfect = 100.0

        if v < lo { return cgaRed }
        if v <= perfect { return cgaGreen }
        if v <= hi {
            let t = min((v - perfect) / (hi - perfect), 1.0)
            return interpolateRGB(from: greenRGB, to: amberRGB, t: t)
        }
        let t = min((v - hi) / 60.0, 1.0)
        return interpolateRGB(from: amberRGB, to: redRGB, t: t)
    }

    /// Stale-data warning tier color — shared by the Overview hero and the
    /// persistent status bar so the two surfaces never disagree on stale
    /// salience (KTD-4). 5–14 min: amber warning; 15+ min: red.
    public static func stalenessColor(_ staleness: GlucoseStaleness) -> Color {
        switch staleness {
        case .fresh, .stale: return amber
        case .veryStale: return cgaRed
        }
    }

    /// Classify glucose into 7-level chart color zone for smooth transitions
    public static func glucoseLevel(forValue value: Int, low: Int, high: Int) -> String {
        if value < low { return "low" }
        if value < low + 15 { return "lowBuffer" }
        if value <= 100 { return "inRange" }
        let mid = 100 + (high - 100) / 2
        if value <= mid { return "rising" }
        if value <= high { return "approaching" }
        if value <= high + 30 { return "highBuffer" }
        return "high"
    }

    /// Linear RGB interpolation
    public static func interpolateRGB(
        from: (r: Double, g: Double, b: Double),
        to: (r: Double, g: Double, b: Double),
        t: Double
    ) -> Color {
        let c = max(0, min(t, 1))
        return Color(
            red: from.r + (to.r - from.r) * c,
            green: from.g + (to.g - from.g) * c,
            blue: from.b + (to.b - from.b) * c
        )
    }
}
