//
//  EventMarkerLaneView.swift
//  DOSBTS
//
//  Flag-and-chip marker rendering per the locked Q2 final-lock design
//  (.superpowers/brainstorm/35252-1777068283/content/q2-marker-overlap-v15-final-lock.html).
//

import SwiftUI

struct EventMarkerLaneView: View {
    let markerGroups: [ConsolidatedMarkerGroup]
    let totalWidth: CGFloat
    let timeRange: ClosedRange<Date>
    let scoredMealEntryIds: Set<UUID>
    let onTapGroup: (ConsolidatedMarkerGroup) -> Void

    private let laneHeight: CGFloat = 60
    private let touchTargetWidth: CGFloat = 88
    private let touchTargetHeight: CGFloat = 48
    private let yAxisPadding: CGFloat = 30

    private let minChipGap: CGFloat = 4

    var body: some View {
        // Pixel-overlap is the SINGLE consolidation authority (DMNC-1415):
        // `xPosition(for:)` scales with zoom (via totalWidth), and the chip
        // footprint is content-aware, so chips split when zoomed in and merge
        // only when they'd visually collide. The pure walk lives on the model.
        let visualGroups = ConsolidatedMarkerGroup.consolidateByOverlap(
            markerGroups,
            xFor: { xPosition(for: $0) },
            estimatedWidth: { $0.estimatedChipWidth(isScored: isGroupScored($0)) },
            minGap: minChipGap
        )

        ZStack(alignment: .bottom) {
            ForEach(visualGroups, id: \.id) { group in
                FlagView(
                    group: group,
                    isScored: isGroupScored(group)
                )
                .frame(width: touchTargetWidth, height: touchTargetHeight, alignment: .bottom)
                .contentShape(Rectangle())
                .onTapGesture { onTapGroup(group) }
                .position(x: xPosition(for: group.time), y: laneHeight - touchTargetHeight / 2 - 2)
                .accessibilityLabel(accessibilityLabel(for: group))
                .accessibilityAddTraits(.isButton)
            }
        }
        .frame(height: laneHeight)
        .padding(.trailing, yAxisPadding)
        .clipped()
    }

    private func isGroupScored(_ group: ConsolidatedMarkerGroup) -> Bool {
        group.markers.contains { marker in
            marker.type == .meal && scoredMealEntryIds.contains(marker.sourceID)
        }
    }

    private func accessibilityLabel(for group: ConsolidatedMarkerGroup) -> String {
        if group.isSingle, let m = group.markers.first {
            switch m.type {
            case .meal: return "Meal at \(m.time.toLocalTime())"
            case .bolus: return "Bolus at \(m.time.toLocalTime())"
            case .correction: return "Correction bolus at \(m.time.toLocalTime())"
            case .basal: return "Basal at \(m.time.toLocalTime())"
            case .exercise: return "Exercise at \(m.time.toLocalTime())"
            }
        }
        return "\(group.markers.count) entries at \(group.time.toLocalTime())"
    }

    private func xPosition(for time: Date) -> CGFloat {
        let totalDuration = timeRange.upperBound.timeIntervalSince(timeRange.lowerBound)
        guard totalDuration > 0 else { return 0 }
        let offset = time.timeIntervalSince(timeRange.lowerBound)
        let adjustedWidth = totalWidth - yAxisPadding
        return (offset / totalDuration) * adjustedWidth
    }
}

// MARK: - FlagView

/// Small black chip with amber-dim border and a 22pt vertical pole anchored at
/// the chip's bottom-centre. Each chip has 1–3 stacked rows in the locked order
/// insulin → meal → exercise; all insulin sub-types share the single insulin
/// row (see `ConsolidatedMarkerGroup.chipRows(isScored:)`) so the chip never
/// overflows the 60pt lane.
private struct FlagView: View {
    let group: ConsolidatedMarkerGroup
    let isScored: Bool

    var body: some View {
        chip
    }

    private var chip: some View {
        let rows = group.chipRows(isScored: isScored)
        return VStack(alignment: .leading, spacing: 1) {
            ForEach(rows.indices, id: \.self) { idx in
                let row = rows[idx]
                HStack(spacing: 4) {
                    iconView(for: row.leadType)
                        .foregroundStyle(row.leadType.color)
                    ForEach(row.segments.indices, id: \.self) { segIdx in
                        let seg = row.segments[segIdx]
                        Text(seg.label)
                            .font(DOSTypography.mono(size: 11, weight: .semibold))
                            .foregroundStyle(seg.type.color)
                    }
                }
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(AmberTheme.dosBlack.opacity(0.92))
        .overlay(
            Rectangle()
                .stroke(isScored ? AmberTheme.amber : AmberTheme.amberDark, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func iconView(for type: EventMarkerType) -> some View {
        switch type {
        case .meal:
            AppleIcon().frame(width: 11, height: 11)
        case .bolus:
            Image(systemName: "syringe.fill").font(DOSTypography.mono(size: 11))
        case .correction:
            Image(systemName: "syringe.fill").font(DOSTypography.mono(size: 11))
        case .basal:
            Image(systemName: "syringe").font(DOSTypography.mono(size: 11))
        case .exercise:
            Image(systemName: "figure.run").font(DOSTypography.mono(size: 11))
        }
    }
}
