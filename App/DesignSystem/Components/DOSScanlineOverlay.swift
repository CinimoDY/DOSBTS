//
//  DOSScanlineOverlay.swift
//  DOSBTS
//
//  CRT scanline effect overlay for DOS aesthetic. Cosine-profile raster
//  (DOS-86 long-reading preset, DMNC-1664). Renders nothing under Increase Contrast.
//

import SwiftUI

struct DOSScanlineOverlay: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if contrast == .increased {
            EmptyView()
        } else {
            Canvas { context, size in
                let step = 1 / max(displayScale, 1)
                let pitch = DOSEffects.Scanline.pitch
                let rowsPerPitch = max(Int((pitch / step).rounded()), 1)
                let rows = Int(ceil(size.height / step))
                // One Path per phase index: every row sharing a phase has the same darkness.
                for phaseIndex in 0..<rowsPerPitch {
                    let phase = Double(phaseIndex) / Double(rowsPerPitch)
                    let darkness = DOSEffects.Scanline.intensity * (0.5 - 0.5 * cos(2 * .pi * phase))
                    guard darkness >= 0.005 else { continue }
                    var path = Path()
                    var row = phaseIndex
                    while row < rows {
                        path.addRect(CGRect(x: 0, y: CGFloat(row) * step, width: size.width, height: step))
                        row += rowsPerPitch
                    }
                    context.fill(path, with: .color(AmberTheme.dosBlack.opacity(darkness)))
                }
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
    }
}
