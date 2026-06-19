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

    var dominantType: EventMarkerType {
        let counts = Dictionary(grouping: markers, by: \.type).mapValues(\.count)
        return counts.max(by: { $0.value < $1.value })?.key ?? .meal
    }

    var summaryLabel: String {
        let totalCarbs = markers
            .filter { $0.type == .meal }
            .reduce(0.0) { $0 + $1.rawValue }
        if totalCarbs > 0 {
            return "\(Int(totalCarbs))g"
        }
        return "\(markers.count)"
    }

    var totalCarbs: Double? {
        let carbs = markers.filter { $0.type == .meal }.reduce(0.0) { $0 + $1.rawValue }
        return carbs > 0 ? carbs : nil
    }
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
            let label = bolus.count > 1
                ? "\(formatMarkerUnits(total))×\(bolus.count)"
                : formatMarkerUnits(total)
            insulin.append(MarkerChipSegment(type: .bolus, label: label))
        }

        let correction = markers.filter { $0.type == .correction }
        if !correction.isEmpty {
            let total = correction.reduce(0.0) { $0 + $1.rawValue }
            // "c" suffix distinguishes correction from meal/snack bolus (same filled-syringe icon)
            let label = correction.count > 1
                ? "\(formatMarkerUnits(total))c×\(correction.count)"
                : "\(formatMarkerUnits(total))c"
            insulin.append(MarkerChipSegment(type: .correction, label: label))
        }

        let basal = markers.filter { $0.type == .basal }
        if !basal.isEmpty {
            let total = basal.reduce(0.0) { $0 + $1.rawValue }
            // "b" suffix distinguishes basal (long-acting) within the shared insulin row
            let label = basal.count > 1
                ? "\(formatMarkerUnits(total))b×\(basal.count)"
                : "\(formatMarkerUnits(total))b"
            insulin.append(MarkerChipSegment(type: .basal, label: label))
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
            let label = meals.count > 1
                ? "\(prefix)\(Int(total))g×\(meals.count)"
                : "\(prefix)\(Int(total))g"
            rows.append(MarkerChipRow(leadType: .meal, segments: [MarkerChipSegment(type: .meal, label: label)]))
        }

        // ---- Exercise lane ----
        let exercise = markers.filter { $0.type == .exercise }
        if !exercise.isEmpty {
            let total = exercise.reduce(0.0) { $0 + $1.rawValue }
            let label = exercise.count > 1
                ? "\(Int(total))m×\(exercise.count)"
                : "\(Int(total))m"
            rows.append(MarkerChipRow(leadType: .exercise, segments: [MarkerChipSegment(type: .exercise, label: label)]))
        }

        return rows
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
