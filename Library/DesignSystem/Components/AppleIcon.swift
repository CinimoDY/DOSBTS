//
//  AppleIcon.swift
//  DOSBTS
//
//  Custom apple-fruit icon. Distinct from Apple Inc.'s `apple.logo` SF
//  Symbol so we don't run into App Store identity-guideline trouble for
//  using the corporate logo to represent food.
//

import SwiftUI

/// A simple apple-fruit silhouette with a small leaf, drawn as a SwiftUI
/// `Shape` so it picks up `.foregroundStyle()` and sizes via `.frame()`.
public struct AppleIcon: View {
    public init() {}

    public var body: some View {
        AppleShape()
            .aspectRatio(0.95, contentMode: .fit)
    }
}

/// Roughly heart-shaped apple body with a tear-drop leaf at the top-right
/// of the stem dimple.
private struct AppleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height

        // Apple body — slightly squished circle with a small dimple at the top.
        p.move(to: CGPoint(x: w * 0.50, y: h * 0.20))
        p.addCurve(
            to: CGPoint(x: w * 0.05, y: h * 0.55),
            control1: CGPoint(x: w * 0.20, y: h * 0.18),
            control2: CGPoint(x: w * 0.00, y: h * 0.30)
        )
        p.addCurve(
            to: CGPoint(x: w * 0.50, y: h * 0.98),
            control1: CGPoint(x: w * 0.00, y: h * 0.92),
            control2: CGPoint(x: w * 0.20, y: h * 1.00)
        )
        p.addCurve(
            to: CGPoint(x: w * 0.95, y: h * 0.55),
            control1: CGPoint(x: w * 0.80, y: h * 1.00),
            control2: CGPoint(x: w * 1.00, y: h * 0.92)
        )
        p.addCurve(
            to: CGPoint(x: w * 0.50, y: h * 0.20),
            control1: CGPoint(x: w * 1.00, y: h * 0.30),
            control2: CGPoint(x: w * 0.80, y: h * 0.18)
        )
        p.closeSubpath()

        // Leaf on top-right of the stem dimple.
        p.move(to: CGPoint(x: w * 0.52, y: h * 0.18))
        p.addQuadCurve(
            to: CGPoint(x: w * 0.72, y: h * 0.02),
            control: CGPoint(x: w * 0.74, y: h * 0.14)
        )
        p.addQuadCurve(
            to: CGPoint(x: w * 0.52, y: h * 0.18),
            control: CGPoint(x: w * 0.52, y: h * 0.02)
        )
        p.closeSubpath()

        return p
    }
}

// MARK: - Combined food + insulin icon

/// Static composition of an apple + a syringe at fixed offsets, used as
/// the single visual for chart-marker batches that mix food and insulin
/// entries. Designed once here, not assembled per-render at the call site.
public struct CombinedFoodInsulinIcon: View {
    public let size: CGFloat

    public init(size: CGFloat) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            // Apple, slightly larger, anchored bottom-left.
            AppleIcon()
                .frame(width: size * 0.72, height: size * 0.72)
                .foregroundStyle(AmberTheme.cgaGreen)
                .offset(x: -size * 0.16, y: size * 0.10)

            // Syringe, smaller, anchored top-right.
            Image(systemName: "syringe.fill")
                .font(DOSTypography.mono(size: size * 0.55, weight: .semibold))
                .foregroundStyle(AmberTheme.amberDark)
                .offset(x: size * 0.20, y: -size * 0.18)
        }
        .frame(width: size, height: size)
    }
}
