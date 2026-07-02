//
//  DOSSurfaces.swift
//  DOSBTS
//
//  Canonical DOS surface chrome: `.dosCard()` panels and `.dosHeader()` section
//  headers. Pure SwiftUI, shared by BOTH the app and widget targets — must not
//  reference App-only code. Consolidates the hand-rolled
//  `overlay(Rectangle().stroke(...)) + background` card assemblies and the
//  divergent section-header stylings into two modifiers (DMNC-1216).
//

import SwiftUI

// MARK: - Card variants

/// The canonical DOS card surfaces. `fill`/`stroke` are exposed so the design
/// token drift-guard can assert the mapping (see `DesignTokenPinTests`).
public enum DOSCardVariant {
    /// General warm panel: `cardBackground` fill, `dosBorder` stroke.
    case panel
    /// AI / info framing (e.g. the Digest AI-insight card): clear fill,
    /// `cgaCyan` stroke.
    case info
    /// Quiet data cell (e.g. `StatCard`): `surfaceTint` fill, `borderSubtle`
    /// stroke.
    case stat
    /// Floating overlay / toast: `scrimHeavy` fill (near-opaque black backdrop),
    /// `amber` stroke.
    case toast

    public var fill: Color {
        switch self {
        case .panel: return AmberTheme.cardBackground
        case .info: return .clear
        case .stat: return AmberTheme.surfaceTint
        // scrimHeavy (dosBlack @ 0.95) is the design system's purpose-built
        // toast backdrop and matches the black@0.95 the toast sites hand-rolled
        // before this consolidation — preserves their prior translucency.
        case .toast: return AmberTheme.scrimHeavy
        }
    }

    public var stroke: Color {
        switch self {
        case .panel: return AmberTheme.dosBorder
        case .info: return AmberTheme.cgaCyan
        case .stat: return AmberTheme.borderSubtle
        case .toast: return AmberTheme.amber
        }
    }
}

// MARK: - Modifiers

extension View {
    /// DOS panel chrome: sharp corners, a 1px stroke, and the variant fill.
    ///
    /// - Parameters:
    ///   - variant: The canonical surface (`.panel` default).
    ///   - stroke: Overrides the variant stroke for stateful borders — e.g. the
    ///     treatment banner's countdown/rechecking/stale/recovered colors.
    ///   - padding: Interior padding. `nil` means the caller manages its own
    ///     (often asymmetric) padding before this modifier.
    public func dosCard(
        _ variant: DOSCardVariant = .panel,
        stroke: Color? = nil,
        padding: CGFloat? = DOSSpacing.md
    ) -> some View {
        modifier(DOSCardModifier(variant: variant, strokeOverride: stroke, padding: padding))
    }

    /// Canonical section header: 12pt semibold mono, 1.2 tracking, uppercase.
    ///
    /// The color carries section semantics — `amberDark` default, `amber`
    /// emphasis, `cgaCyan` for AI/info. Intentionally has NO phosphor glow: a
    /// glow shadow here would violate the "no glow in list rows" performance
    /// rule (`docs/design-system.md` → Visual Effects), so the header stays flat.
    public func dosHeader(_ color: Color = AmberTheme.amberDark) -> some View {
        font(DOSTypography.mono(size: 12, weight: .semibold))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

// MARK: - Card modifier

private struct DOSCardModifier: ViewModifier {
    let variant: DOSCardVariant
    let strokeOverride: Color?
    let padding: CGFloat?

    func body(content: Content) -> some View {
        padded(content)
            .background(variant.fill)
            .overlay(
                Rectangle()
                    .stroke(strokeOverride ?? variant.stroke, lineWidth: 1)
            )
    }

    @ViewBuilder
    private func padded(_ content: Content) -> some View {
        if let padding {
            content.padding(padding)
        } else {
            content
        }
    }
}
