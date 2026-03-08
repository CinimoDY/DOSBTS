//
//  DOSButtonStyle.swift
//  DOSBTS
//
//  eiDotter-inspired button style with CGA amber aesthetic
//

import SwiftUI

/// DOS/CGA terminal button style with sharp corners and amber palette
struct DOSButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    enum Variant {
        case primary
        case ghost
    }

    var variant: Variant = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DOSTypography.button)
            .foregroundColor(foregroundColor(configuration))
            .padding(.horizontal, DOSSpacing.md)
            .padding(.vertical, DOSSpacing.xs)
            .background(backgroundColor(configuration))
            .overlay(Rectangle().stroke(isEnabled ? AmberTheme.amber : AmberTheme.amberMuted, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.9), value: configuration.isPressed)
    }

    private func foregroundColor(_ configuration: Configuration) -> Color {
        if !isEnabled { return AmberTheme.amberMuted }
        if variant == .primary {
            return AmberTheme.dosBlack
        }
        return configuration.isPressed ? AmberTheme.amberLight : AmberTheme.amber
    }

    private func backgroundColor(_ configuration: Configuration) -> Color {
        if !isEnabled {
            return variant == .primary ? AmberTheme.amberMuted.opacity(0.3) : Color.clear
        }
        if variant == .primary {
            return configuration.isPressed ? AmberTheme.amberPressed : AmberTheme.amber
        }
        return configuration.isPressed ? AmberTheme.amber.opacity(0.1) : Color.clear
    }
}

#if DEBUG
struct DOSButtonStyle_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: DOSSpacing.lg) {
            Button("CONNECT SENSOR") {}
                .buttonStyle(DOSButtonStyle(variant: .primary))

            Button("DISCONNECT") {}
                .buttonStyle(DOSButtonStyle(variant: .ghost))

            Button("PAIR DEVICE") {}
                .buttonStyle(DOSButtonStyle(variant: .primary))
                .disabled(true)
        }
        .padding()
        .background(AmberTheme.dosBlack)
        .preferredColorScheme(.dark)
    }
}
#endif
