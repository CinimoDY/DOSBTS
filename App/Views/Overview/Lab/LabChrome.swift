//
//  LabChrome.swift
//  DOSBTS
//
//  Shared Chart Lab chrome (DMNC-1500): the legend row every lab tab builds from
//  and the footer every lab tab must carry. P1–P5 append their own legend items;
//  none of them may drop the footer.
//

import SwiftUI

// MARK: - LabLegendItem

/// One legend entry: a coloured glyph and its dim label, the prototype's shape.
struct LabLegendItem: Identifiable {
    let id: String
    let glyph: String
    let label: String
    let color: Color

    init(glyph: String, label: String, color: Color) {
        self.id = "\(glyph)-\(label)"
        self.glyph = glyph
        self.label = label
        self.color = color
    }

    /// The legend half of the FOLLOW story — the `◂ N NEW` nub is the other.
    static func follow(_ status: LabFollowStatus) -> LabLegendItem {
        switch status {
        case .following:
            return LabLegendItem(glyph: "●", label: "FOLLOW", color: AmberTheme.amber)
        case .detached(let unseen):
            return LabLegendItem(
                glyph: "○",
                label: unseen > 0 ? "FOLLOW OFF · \(unseen) NEW" : "FOLLOW OFF",
                color: AmberTheme.amberDark
            )
        }
    }
}

// MARK: - LabLegendRow

struct LabLegendRow: View {
    let items: [LabLegendItem]

    var body: some View {
        HStack(spacing: DOSSpacing.sm) {
            ForEach(items) { item in
                HStack(spacing: DOSSpacing.xxs) {
                    Text(item.glyph)
                        .foregroundStyle(item.color)
                    Text(item.label)
                        .foregroundStyle(AmberTheme.amberDark)
                }
            }
        }
        .font(DOSTypography.microLabel)
        .padding(.vertical, DOSSpacing.xxs)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - LabFooter

/// On EVERY lab tab, without exception. The lab teaches; it never prescribes.
struct LabFooter: View {
    var body: some View {
        Text("LAB · EXPERIMENTAL · NOT DOSE ADVICE")
            .font(DOSTypography.micro)
            .foregroundStyle(AmberTheme.textFaint)
            .frame(maxWidth: .infinity)
    }
}
