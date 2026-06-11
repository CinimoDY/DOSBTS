//
//  LoadingIndicator.swift
//  DOSBTSApp
//

import SwiftUI

/// Full-screen busy indicator, applied as an `.overlay` on the root
/// TabView. (Previously a wrapper view around the TabView — that wrapper's
/// GeometryReader/ZStack swallowed the tabViewBottomAccessory preference,
/// so the indicator now sits on top instead of around.)
struct LoadingOverlay: View {
    @Binding var isShowing: Bool
    @State private var isActive = false

    var body: some View {
        if isShowing {
            ZStack(alignment: .center) {
                // Dim and block the UI beneath while busy.
                Color.black.opacity(0.5)
                    .ignoresSafeArea()

                VStack {
                    Text("LOADING...")
                        .font(DOSTypography.body)
                        .foregroundColor(AmberTheme.amber)
                        .dosPowerOn(isActive: $isActive)
                        .padding(.top, 48)

                    BlinkingCursor()
                        .padding(.top, 24)
                        .padding(.bottom, 32)
                }
                .frame(maxWidth: 200)
                .background(AmberTheme.dosBlack)
                .overlay(Rectangle().stroke(AmberTheme.amberMuted.opacity(0.3), lineWidth: 1))
                .opacity(0.9)
            }
            .onAppear {
                isActive = true
            }
            .onDisappear {
                isActive = false
            }
        }
    }
}

private struct BlinkingCursor: View {
    @State private var visible = true

    var body: some View {
        Text("_")
            .font(DOSTypography.body)
            .foregroundColor(AmberTheme.amber)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever()) {
                    visible.toggle()
                }
            }
    }
}
