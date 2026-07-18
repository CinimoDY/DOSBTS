//
//  EventMarker.swift
//  DOSBTS
//
//  Chart event marker types shared between ChartView, EventMarkerLaneView,
//  and the unified entry/edit modal (DMNC-848).
//

import SwiftUI

// MARK: - EventMarkerType

enum EventMarkerType: Hashable {
    case meal
    case bolus
    case correction
    case basal
    case exercise

    var icon: String {
        switch self {
        case .meal: return "apple.logo"
        case .bolus: return "syringe.fill"
        case .correction: return "syringe.fill"
        case .basal: return "syringe"  // outline variant signals long-acting / steady-state
        case .exercise: return "figure.run"
        }
    }

    var color: Color {
        switch self {
        case .meal: return AmberTheme.cgaGreen
        case .bolus: return AmberTheme.amber
        case .correction: return AmberTheme.amberLight
        case .basal: return AmberTheme.amberDark
        case .exercise: return AmberTheme.cgaCyan
        }
    }
}

// MARK: - EventMarker

struct EventMarker: Identifiable {
    let id: String
    let time: Date
    let type: EventMarkerType
    let label: String
    let rawValue: Double
    let sourceID: UUID
}

// MARK: - ConsolidatedMarkerGroup

struct ConsolidatedMarkerGroup: Identifiable {
    let id: String
    let time: Date
    let markers: [EventMarker]

    var isSingle: Bool { markers.count == 1 }
}

extension ConsolidatedMarkerGroup: Equatable {
    static func == (lhs: ConsolidatedMarkerGroup, rhs: ConsolidatedMarkerGroup) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - InsulinType → EventMarkerType

extension InsulinType {
    /// Maps an insulin delivery type to its event marker lane representation.
    /// Extracted here so it can be unit-tested without a SwiftUI context.
    var markerType: EventMarkerType {
        switch self {
        case .basal: return .basal
        case .correctionBolus: return .correction
        case .mealBolus, .snackBolus: return .bolus
        }
    }
}

// MARK: - Marker chip rows (testable layout model)

/// One colored value piece within a chip row — e.g. the `2Uc` correction part
/// of a combined insulin row. Carries its `EventMarkerType` (so the view can
/// resolve icon + color) but no SwiftUI layout types, so it stays unit-testable.
struct MarkerChipSegment: Equatable {
    let type: EventMarkerType
    let label: String
}

/// One stacked row of the chip. `leadType` drives the single leading icon;
/// `segments` are the colored value pieces shown after it.
struct MarkerChipRow: Equatable {
    let leadType: EventMarkerType
    let segments: [MarkerChipSegment]
}

extension ConsolidatedMarkerGroup {
    /// Builds the chip's stacked rows in the locked 3-lane order:
    /// **insulin → meal → exercise**. All insulin sub-types (meal/snack bolus,
    /// correction, basal) collapse into a SINGLE insulin row as colored
    /// segments, so the chip never exceeds 3 rows — the 60pt lane budget. Each
    /// sub-type keeps its own color and suffix (`U` bolus, `Uc` correction,
    /// `Ub` basal) so the correction distinction (DMNC-715) survives the merge.
    ///
    /// Extracted out of the private `FlagView` so the row-count invariant can be
    /// unit-tested without a SwiftUI context (mirrors `InsulinType.markerType`).
    func chipRows(isScored: Bool) -> [MarkerChipRow] {
        var rows: [MarkerChipRow] = []

        // ---- Insulin lane: bolus → correction → basal segments ----
        var insulin: [MarkerChipSegment] = []

        let bolus = markers.filter { $0.type == .bolus }
        if !bolus.isEmpty {
            let total = bolus.reduce(0.0) { $0 + $1.rawValue }
            insulin.append(MarkerChipSegment(type: .bolus, label: formatMarkerUnits(total)))
        }

        let correction = markers.filter { $0.type == .correction }
        if !correction.isEmpty {
            let total = correction.reduce(0.0) { $0 + $1.rawValue }
            // "c" suffix distinguishes correction from meal/snack bolus (same filled-syringe icon)
            insulin.append(MarkerChipSegment(type: .correction, label: "\(formatMarkerUnits(total))c"))
        }

        let basal = markers.filter { $0.type == .basal }
        if !basal.isEmpty {
            let total = basal.reduce(0.0) { $0 + $1.rawValue }
            // "b" suffix distinguishes basal (long-acting) within the shared insulin row
            insulin.append(MarkerChipSegment(type: .basal, label: "\(formatMarkerUnits(total))b"))
        }

        if let lead = insulin.first {
            // Lead icon precedence: filled syringe (bolus/correction) when any
            // rapid insulin is present, else the basal outline syringe.
            rows.append(MarkerChipRow(leadType: lead.type, segments: insulin))
        }

        // ---- Meal lane ----
        let meals = markers.filter { $0.type == .meal }
        if !meals.isEmpty {
            let total = meals.reduce(0.0) { $0 + $1.rawValue }
            let prefix = isScored ? "★" : ""  // ★ marks meals with a glycemic impact score
            rows.append(MarkerChipRow(leadType: .meal, segments: [MarkerChipSegment(type: .meal, label: "\(prefix)\(Int(total))g")]))
        }

        // ---- Exercise lane ----
        let exercise = markers.filter { $0.type == .exercise }
        if !exercise.isEmpty {
            let total = exercise.reduce(0.0) { $0 + $1.rawValue }
            rows.append(MarkerChipRow(leadType: .exercise, segments: [MarkerChipSegment(type: .exercise, label: "\(Int(total))m")]))
        }

        return rows
    }
}

// MARK: - Pixel-overlap consolidation (single authority, DMNC-1415)

extension ConsolidatedMarkerGroup {
    /// Estimated rendered chip width in points, derived from the chip's own
    /// `chipRows` labels so the collision test scales with content: a single
    /// `5U` chip estimates narrower than a triple-stack `8U 2Uc 10Ub / ★60g /
    /// 45m` chip. Chip labels all render in 11pt SF Mono semibold, so a
    /// per-character advance × the longest row's label length is a fair proxy;
    /// the chip width is driven by its widest row (rows stack vertically).
    /// Pure — no SwiftUI layout, so it's unit-testable and shared with the
    /// widget target. Mirrors `FlagView`'s geometry: one leading icon + a 4pt
    /// gap before/between each segment text, and 5pt horizontal padding a side.
    ///
    /// Constants are deliberately conservative (slightly over-estimating width)
    /// so chips err on merging a hair early rather than overlapping. Pinned in
    /// `MarkerConsolidationTests`.
    static let chipMonoCharWidth: CGFloat = 7      // ~advance of 11pt SF Mono semibold
    static let chipIconWidth: CGFloat = 12         // leading icon glyph box
    static let chipIconTextGap: CGFloat = 4        // FlagView HStack spacing (icon↔text, text↔text)
    static let chipHorizontalPadding: CGFloat = 5  // FlagView .padding(.horizontal, 5), per side

    func estimatedChipWidth(isScored: Bool) -> CGFloat {
        let rows = chipRows(isScored: isScored)
        // Width of the widest row: leading icon + one HStack gap per child
        // boundary (icon→seg0, seg0→seg1, …) + the summed label characters.
        let widestRow = rows.map { row -> CGFloat in
            let labelChars = row.segments.reduce(0) { $0 + $1.label.count }
            // children = 1 icon + segments.count texts → segments.count gaps
            let gaps = CGFloat(row.segments.count) * Self.chipIconTextGap
            return Self.chipIconWidth + gaps + CGFloat(labelChars) * Self.chipMonoCharWidth
        }.max() ?? 0
        return widestRow + 2 * Self.chipHorizontalPadding
    }

    /// Walk groups left-to-right (by time) and merge any whose rendered chip
    /// would visually collide with the previous one's. `xFor` maps a marker
    /// time to its pixel position at the current zoom; `estimatedWidth` returns
    /// a group's chip footprint. Chips are centered on their positions, so two
    /// collide when their centers are closer than the sum of their half-widths
    /// plus `minGap`. This is the SINGLE consolidation authority (DMNC-1415):
    /// because `xFor` scales with zoom, the same marker set merges when zoomed
    /// out (positions crowd) and splits into individual chips when zoomed in
    /// (positions spread) — no fixed time window. Pure — no view dependencies.
    ///
    /// A merged group keeps the earlier group's `id` (so sheet identity doesn't
    /// churn across re-renders), concatenates markers, and re-anchors to the
    /// median marker time.
    static func consolidateByOverlap(
        _ groups: [ConsolidatedMarkerGroup],
        xFor: (Date) -> CGFloat,
        estimatedWidth: (ConsolidatedMarkerGroup) -> CGFloat,
        minGap: CGFloat = 4
    ) -> [ConsolidatedMarkerGroup] {
        var visual: [ConsolidatedMarkerGroup] = []

        for group in groups.sorted(by: { $0.time < $1.time }) {
            if let last = visual.last {
                let lastX = xFor(last.time)
                let groupX = xFor(group.time)
                let mergeDistance = (estimatedWidth(last) + estimatedWidth(group)) / 2 + minGap
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
}

/// Formats insulin units as a compact chip label: integer units drop the
/// decimal (`5U`), fractional units keep one place (`2.5U`).
private func formatMarkerUnits(_ units: Double) -> String {
    if units == units.rounded() {
        return "\(Int(units))U"
    }
    return String(format: "%.1fU", units)
}
