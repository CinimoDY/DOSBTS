//
//  DOSEffects.swift
//  DOSBTS
//
//  Single source for the CRT monitor effect values (DMNC-1664).
//

import SwiftUI

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
        /// SwiftUI shadow ≠ additive light; ×N opacity for visual parity with the DOS-86 specimen.
        public static let shadowGain: Double = 3.0
        /// Widget scale: pre-DOS-86 values kept until verified on a 44pt widget.
        public static let widgetRadius: CGFloat = 1
        public static let widgetIntensity: Double = 0.8
        public static let widgetBloomRadius: CGFloat = 4
        public static let widgetBloomIntensity: Double = 0.3
    }
    public enum Vignette {
        /// How much dimmer the corners get (0–1). DOS-86 effect.vignette.intensity.
        public static let intensity: Double = 0.22
        /// How far in from the corners the dimming reaches. DOS-86 effect.vignette.spread.
        public static let spread: Double = 0.20
        /// Radius fraction where dimming starts. Raised from 0.5 - spread (0.30) to 0.35 so the
        /// outer tab-bar items sit at <= ~8% black instead of ~14%.
        public static let startRadiusFraction: Double = 0.35
    }
}

extension View {
    /// Two-layer phosphor glow (tight glow + soft bloom) from `DOSEffects.Glow`.
    func dosPhosphorLayers(color: Color) -> some View {
        self
            .shadow(color: color.opacity(min(DOSEffects.Glow.intensity * DOSEffects.Glow.shadowGain, 1)),
                    radius: DOSEffects.Glow.radius, x: 0, y: 0)
            .shadow(color: color.opacity(min(DOSEffects.Glow.bloomIntensity * DOSEffects.Glow.shadowGain, 1)),
                    radius: DOSEffects.Glow.bloomRadius, x: 0, y: 0)
    }
}
