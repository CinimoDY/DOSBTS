//
//  WidgetDesignSystem.swift
//  DOSBTSWidget
//
//  Widget-scale type roles. Colors and base fonts come from AmberTheme/DOSTypography
//  in Library/DesignSystem (compiled into the widget target via fileSystemSynchronized).
//

import SwiftUI

// MARK: - WidgetFonts

/// Widget-scale type roles. Sizes legitimately differ from app-scale DOSTypography
/// (e.g. glucoseHero 44/52 vs app 60) — these remain as widget-specific aliases.
enum WidgetFonts {
    static let glucoseHero = DOSTypography.mono(size: 44, weight: .bold)
    static let glucoseLarge = DOSTypography.mono(size: 52, weight: .bold)
    static let body = DOSTypography.body
    static let bodySmall = DOSTypography.bodySmall
    static let caption = DOSTypography.caption
    static let label = DOSTypography.mono(size: 14)
    static let labelSmall = DOSTypography.mono(size: 13)
    static let tabBar = DOSTypography.tabBar

    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        DOSTypography.mono(size: size, weight: weight)
    }
}

// MARK: - Phosphor Glow Modifier

extension View {
    /// Phosphor CRT glow effect — two layers, widget-scale values from DOSEffects.Glow
    func phosphorGlow(color: Color = AmberTheme.amber) -> some View {
        self
            .shadow(color: color.opacity(DOSEffects.Glow.widgetIntensity), radius: DOSEffects.Glow.widgetRadius, x: 0, y: 0)
            .shadow(color: color.opacity(DOSEffects.Glow.widgetBloomIntensity), radius: DOSEffects.Glow.widgetBloomRadius, x: 0, y: 0)
    }
}

// MARK: - DataStaleness Widget Extensions

extension DataStaleness {
    var timestampColor: Color {
        switch self {
        // Fresh is dim text (amberSoft, AA). Stale is the honest warning yellow, a hue
        // change rather than a brightness step, so fresh → stale stays salient
        // (Dom, 2026-11-27; matches `AmberTheme.stalenessColor`).
        case .fresh: return AmberTheme.amberSoft
        case .stale: return AmberTheme.cgaYellow
        case .veryStale: return AmberTheme.cgaRed
        }
    }

    var glucoseOpacity: Double {
        switch self {
        case .fresh: return 1.0
        case .stale: return 0.6
        case .veryStale: return 0.4
        }
    }
}
