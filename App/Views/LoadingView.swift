//
//  LoadingIndicator.swift
//  DOSBTSApp
//

import SwiftUI

struct LoadingView<Content>: View where Content: View {
    @Binding var isShowing: Bool
    @State private var isActive = false
    var content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .center) {
                self.content()
                    .disabled(self.isShowing)
                    .opacity(self.isShowing ? 0.5 : 1)
                    .blur(radius: self.isShowing ? 2 : 0)

                VStack {
                    Text("LOADING...")
                        .font(DOSTypography.body)
                        .foregroundColor(AmberTheme.amber)
                        .opacity(isActive ? 1 : 0)
                        .blur(radius: isActive ? 0 : 4)
                        .brightness(isActive ? 0 : -0.7)
                        .padding(.top, 48)

                    BlinkingCursor()
                        .padding(.top, 24)
                        .padding(.bottom, 32)
                }
                .frame(width: geometry.size.width / 2)
                .background(AmberTheme.dosBlack)
                .overlay(Rectangle().stroke(AmberTheme.amberMuted.opacity(0.3), lineWidth: 1))
                .opacity(self.isShowing ? 0.9 : 0)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.6)) {
                        isActive = true
                    }
                }
                .onDisappear {
                    isActive = false
                }
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
