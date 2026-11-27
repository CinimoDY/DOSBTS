//
//  DOSVignetteOverlay.swift
//  DOSBTS
//
//  Faint edge/corner darkening for the CRT monitor effect (DMNC-1664).
//  Skipped under Reduce Transparency / Increase Contrast.
//

import SwiftUI

struct DOSVignetteOverlay: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if reduceTransparency || contrast == .increased {
            EmptyView()
        } else {
            EllipticalGradient(
                colors: [.clear, AmberTheme.dosBlack.opacity(DOSEffects.Vignette.intensity)],
                center: .center,
                startRadiusFraction: 0.5 - DOSEffects.Vignette.spread,
                endRadiusFraction: 0.75  // corners sit at ~0.707, so they reach full intensity
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
