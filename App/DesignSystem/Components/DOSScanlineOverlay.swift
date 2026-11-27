//
//  DOSScanlineOverlay.swift
//  DOSBTS
//
//  CRT scanline effect overlay for DOS aesthetic. Cosine-profile raster
//  (DOS-86 long-reading preset, DMNC-1664).
//

import SwiftUI

struct DOSScanlineOverlay: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Canvas { context, size in
            let step = 1 / max(displayScale, 1)
            let pitch = DOSEffects.Scanline.pitch
            let rows = Int(size.height / step)
            for i in 0..<rows {
                let y = CGFloat(i) * step
                let phase = Double(y.truncatingRemainder(dividingBy: pitch) / pitch)
                let darkness = DOSEffects.Scanline.intensity * (0.5 - 0.5 * cos(2 * .pi * phase))
                guard darkness >= 0.005 else { continue }
                let rect = CGRect(x: 0, y: y, width: size.width, height: step)
                context.fill(Path(rect), with: .color(AmberTheme.dosBlack.opacity(darkness)))
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
