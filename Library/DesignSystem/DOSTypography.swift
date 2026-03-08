//
//  DOSTypography.swift
//  DOSBTS
//
//  DOS-Inspired Typography System
//  Monospace fonts for retro terminal aesthetic
//

import SwiftUI

/// DOS-inspired typography system using monospace fonts for retro terminal aesthetic
public enum DOSTypography {

    // MARK: - Display Sizes (Headers)

    /// Medium display (28pt) - Section headers
    public static let displayMedium = Font.system(size: 28, weight: .bold, design: .monospaced)

    // MARK: - Body Text

    /// Large body (20pt) - Emphasized content
    public static let bodyLarge = Font.system(size: 20, weight: .regular, design: .monospaced)

    /// Regular body (17pt) - Standard text
    public static let body = Font.system(size: 17, weight: .regular, design: .monospaced)

    /// Small body (15pt) - Secondary text, timestamps, metadata
    public static let bodySmall = Font.system(size: 15, weight: .regular, design: .monospaced)

    // MARK: - Data Display (Tabular Numbers)

    /// Glucose hero (60pt) - The main glucose reading
    public static let glucoseHero = Font.system(size: 60, weight: .bold, design: .monospaced)
        .monospacedDigit()

    // MARK: - Labels & Captions

    /// Caption (12pt) - Small descriptive text, chart axes
    public static let caption = Font.system(size: 12, weight: .regular, design: .monospaced)

    // MARK: - UI Elements

    /// Button text (17pt) - Interactive elements
    public static let button = Font.system(size: 17, weight: .semibold, design: .monospaced)

    /// Tab bar (10pt) - Navigation labels
    public static let tabBar = Font.system(size: 10, weight: .medium, design: .monospaced)

    // MARK: - Custom Sizes

    /// Creates a monospaced font with custom size and weight
    public static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        return Font.system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Glow Modifiers

extension View {

    /// Large phosphor glow for hero glucose, headers
    public func dosGlowLarge() -> some View {
        self
            .shadow(color: AmberTheme.amber.opacity(0.8), radius: 1, x: 0, y: 0)
            .shadow(color: AmberTheme.amber.opacity(0.4), radius: 6, x: 0, y: 0)
            .shadow(color: AmberTheme.amber.opacity(0.15), radius: 16, x: 0, y: 0)
    }
}
