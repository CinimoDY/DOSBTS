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

    /// Approximate chip width for the merge heuristic. Real chip widths vary
    /// by content (single-row "💉 5U" is narrower than triple-stack "💉 5U /
    /// 🍴 45g / 🏃 20m") but we don't get layout sizes during data prep, so
    /// we use a conservative average.
    private let estimatedChipWidth: CGFloat = 60
    private let minChipGap: CGFloat = 4

    var body: some View {
        let visualGroups = consolidateByOverlap(markerGroups)

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

    /// Walk the groups left-to-right and merge any whose visual chip would
    /// overlap (with a 4pt min gap) into the previous one. Replaces the old
    /// fixed `consolidationWindows[chartZoomLevel]` so consolidation
    /// follows the rendered layout, not an arbitrary minute count.
    private func consolidateByOverlap(_ groups: [ConsolidatedMarkerGroup]) -> [ConsolidatedMarkerGroup] {
        let mergeDistance = estimatedChipWidth + minChipGap
        var visual: [ConsolidatedMarkerGroup] = []

        for group in groups.sorted(by: { $0.time < $1.time }) {
            if let last = visual.last {
                let lastX = xPosition(for: last.time)
                let groupX = xPosition(for: group.time)
                if groupX - lastX < mergeDistance {
                    let merged = last.markers + group.markers
                    let sortedTimes = merged.map(\.time).sorted()
                    let medianTime = sortedTimes[sortedTimes.count / 2]
                    visual[visual.count - 1] = ConsolidatedMarkerGroup(
                        id: last.id,
                        time: medianTime,
                        markers: merged
                    )
                    continue
                }
            }
            visual.append(group)
        }
        return visual
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
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
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
            Image(systemName: "syringe.fill").font(.system(size: 11))
        case .correction:
            Image(systemName: "syringe.fill").font(.system(size: 11))
        case .basal:
            Image(systemName: "syringe").font(.system(size: 11))
        case .exercise:
            Image(systemName: "figure.run").font(.system(size: 11))
        }
    }
}
