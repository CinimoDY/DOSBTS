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
