//
//  StatsComponents.swift
//  DOSBTS
//
//  Shared stats primitives used by the Overview chart's TIR/Statistics tabs
//  and by the Lists tab's Statistics + Usage sections. Same visual vocabulary
//  across both surfaces so users see one design language for stats.
//

import SwiftUI

// MARK: - Hero stat (big number + unit + caption label)

/// Used as the headline display: a large monospaced number, an optional unit
/// suffix, and an ALL-CAPS amber-dim caption beneath. Used for "AVG 142
/// mg/dL" and "73% TIME IN RANGE" style heroes.
public struct HeroStatView: View {
    public let value: String
    public let unit: String?
    public let label: String
    public let valueColor: Color

    public init(
        value: String,
        unit: String? = nil,
        label: String,
        valueColor: Color = AmberTheme.amber
    ) {
        self.value = value
        self.unit = unit
        self.label = label
        self.valueColor = valueColor
    }

    public var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 56, weight: .bold, design: .monospaced))
                    .foregroundStyle(valueColor)
                if let unit, !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(AmberTheme.amberDark)
                }
            }
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(AmberTheme.amberDark)
        }
    }
}

// MARK: - Stat card (compact label / value / help cell for grids)

public struct StatCard: View {
    public let label: String
    public let value: String
    public let valueColor: Color
    public let help: String?

    public init(
        label: String,
        value: String,
        valueColor: Color = AmberTheme.amberLight,
        help: String? = nil
    ) {
        self.label = label
        self.value = value
        self.valueColor = valueColor
        self.help = help
    }

    public var body: some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(AmberTheme.amberDark)
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .monospaced))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(help ?? "")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(AmberTheme.amberDark.opacity(0.7))
                .lineLimit(1)
                .opacity(help != nil ? 1 : 0)
                .accessibilityHidden(help == nil)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DOSSpacing.sm)
        .padding(.horizontal, DOSSpacing.xs)
        .background(AmberTheme.amber.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(AmberTheme.amberDark.opacity(0.4), lineWidth: 1)
        )
    }
}

// MARK: - Stacked TIR / TBR / TAR distribution bar

public struct StackedTIRBar: View {
    public let tbr: Double
    public let tir: Double
    public let tar: Double
    public let height: CGFloat

    public init(tbr: Double, tir: Double, tar: Double, height: CGFloat = 28) {
        self.tbr = tbr
        self.tir = tir
        self.tar = tar
        self.height = height
    }

    public var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(AmberTheme.cgaRed)
                    .frame(width: max(0, geo.size.width * CGFloat(tbr / 100.0)))
                Rectangle()
                    .fill(AmberTheme.cgaGreen)
                    .frame(width: max(0, geo.size.width * CGFloat(tir / 100.0)))
                Rectangle()
                    .fill(AmberTheme.amber)
                    .frame(width: max(0, geo.size.width * CGFloat(tar / 100.0)))
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(AmberTheme.amberDark.opacity(0.4), lineWidth: 0.5)
        )
    }
}

// MARK: - Helpers

/// Clinical threshold colouring for TIR percentages: ≥70% green (consensus
/// target), ≥50% amber (close), otherwise red (off target).
public func tirColor(_ tir: Double) -> Color {
    if tir >= 70 { return AmberTheme.cgaGreen }
    if tir >= 50 { return AmberTheme.amber }
    return AmberTheme.cgaRed
}

/// One-line interpretive hint for a TIR percentage. Used as the help
/// caption beneath the TIR `StatCard`.
public func tirHelp(_ tir: Double) -> String {
    if tir >= 70 { return "On target" }
    if tir >= 50 { return "Close" }
    return "Off target"
}

/// Three-up numeric breakdown row for the TBR / TIR / TAR distribution.
/// Used beneath `StackedTIRBar`.
public struct TIRBreakdownRow: View {
    public let tbr: Double
    public let tir: Double
    public let tar: Double

    public init(tbr: Double, tir: Double, tar: Double) {
        self.tbr = tbr
        self.tir = tir
        self.tar = tar
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 0) {
            stat(label: "BELOW", value: tbr, color: AmberTheme.cgaRed)
            Spacer()
            stat(label: "IN RANGE", value: tir, color: AmberTheme.cgaGreen)
            Spacer()
            stat(label: "ABOVE", value: tar, color: AmberTheme.amber)
        }
    }

    private func stat(label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(Int(value))%")
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(AmberTheme.amberDark)
        }
    }
}
