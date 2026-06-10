//
//  AmberChip.swift
//  DOSBTS
//

import SwiftUI

// MARK: - AmberChipLabel

/// Visual-only chip body shared by `AmberChip` (Button wrapper) and gesture
/// wrappers like `HoldToCommitProgress` that own their tap handling and
/// therefore can't nest a Button (DMNC-796).
public struct AmberChipLabel: View {
    public let label: String
    public let subtitle: String?
    public let icon: String?
    public let variant: AmberChip.Variant
    public let tint: Color
    public let isSelected: Bool

    public init(
        label: String,
        subtitle: String? = nil,
        icon: String? = nil,
        variant: AmberChip.Variant = .type,
        tint: Color = AmberTheme.amber,
        isSelected: Bool = false
    ) {
        self.label = label
        self.subtitle = subtitle
        self.icon = icon
        self.variant = variant
        self.tint = tint
        self.isSelected = isSelected
    }

    public var body: some View {
        switch variant {
        case .quick:
            quickBody
        case .type, .preset:
            segmentedBody
        }
    }

    // Two-line intrinsic-width chip for the QUICK favourites row: label +
    // optional carbs sub-line, tint-colored stroke (cgaGreen for hypo chips).
    private var quickBody: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(DOSTypography.caption)
                .lineLimit(1)
                .truncationMode(.tail)

            if let subtitle {
                Text(subtitle)
                    .font(DOSTypography.caption)
            }
        }
        .frame(maxWidth: 120, alignment: .leading)
        .padding(.horizontal, DOSSpacing.sm)
        .padding(.vertical, DOSSpacing.xs)
        .foregroundStyle(isSelected ? Color.black : tint)
        .background(isSelected ? tint : Color.black)
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(tint, lineWidth: 1)
        )
    }

    private var segmentedBody: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 11)) }
            Text(label)
                .font(.system(size: variant == .type ? 13 : 12, weight: isSelected ? .semibold : .regular, design: .monospaced))
                .tracking(0.4)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(minHeight: variant == .type ? 44 : 40)
        .foregroundStyle(isSelected ? Color.black : tint)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(isSelected ? tint : Color.black)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(isSelected ? tint : AmberTheme.amberDark, lineWidth: 1)
        )
    }
}

// MARK: - AmberChip

public struct AmberChip: View {
    public enum Variant {
        case type      // 44pt segmented selection chip
        case preset    // 40pt single-tap action chip
        case quick     // two-line intrinsic-width favourite chip (DMNC-796)
    }

    public let label: String
    public let subtitle: String?
    public let icon: String?
    public let variant: Variant
    public let tint: Color
    public let isSelected: Bool
    public let action: () -> Void

    public init(
        label: String,
        subtitle: String? = nil,
        icon: String? = nil,
        variant: Variant = .type,
        tint: Color = AmberTheme.amber,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.subtitle = subtitle
        self.icon = icon
        self.variant = variant
        self.tint = tint
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            AmberChipLabel(
                label: label,
                subtitle: subtitle,
                icon: icon,
                variant: variant,
                tint: tint,
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityText: String {
        // Replace ASCII-art labels with readable text
        switch label {
        case "⋯": return "Custom time"
        case "−15m": return "15 minutes ago"
        case "−30m": return "30 minutes ago"
        case "−1h": return "1 hour ago"
        default: return label
        }
    }
}
