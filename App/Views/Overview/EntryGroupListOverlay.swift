//
//  EntryGroupListOverlay.swift
//  DOSBTS
//
//  Libre-style read-surface sheet for chart marker groups (DMNC-848).
//

import SwiftUI

// MARK: - Supporting Types

enum ConfounderType {
    case correctionBolus
    case exercise
    case stackedMeal
}

struct PersonalFoodGlycemic {
    let avgDelta: Int
    let observationCount: Int
}

/// Wraps the 3 entry types so the static `subline(for:)` helper can be unit
/// tested without a full overlay context.
enum MarkerEntryStub {
    case meal(MealEntry)
    case insulin(InsulinDelivery)
    case exercise(ExerciseEntry)
}

// MARK: - View

struct EntryGroupListOverlay: View {
    let group: ConsolidatedMarkerGroup
    let mealEntries: [MealEntry]
    let insulinDeliveries: [InsulinDelivery]
    let exerciseEntries: [ExerciseEntry]
    let mealImpacts: [UUID: MealImpact]
    let personalFoodAvgs: [UUID: PersonalFoodGlycemic]
    let glucoseUnit: GlucoseUnit
    let iobAtTime: (Date) -> Double?
    let confoundersFor: (MealEntry) -> [ConfounderType]
    var onEdit: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                Divider().background(AmberTheme.amberDark)
                ForEach(chronologicalRows, id: \.id) { marker in
                    row(for: marker)
                    Divider().background(AmberTheme.amberDark.opacity(0.4))
                }
            }
        }
        .safeAreaInset(edge: .bottom) { okBar }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var chronologicalRows: [EventMarker] {
        group.markers.sorted { $0.time < $1.time }
    }

    private var header: some View {
        HStack {
            Text(headerText)
                .font(DOSTypography.body)
                .foregroundStyle(AmberTheme.amber)
            Spacer()
            Button(action: onEdit) {
                Text("edit")
                    .font(DOSTypography.caption)
                    .tracking(0.6)
                    .foregroundStyle(AmberTheme.amberLight)
                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit this entry group")
        }
        .padding(.horizontal, DOSSpacing.md)
        .padding(.vertical, DOSSpacing.sm)
    }

    private static let headerTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private var headerText: String {
        "\(Self.headerTimeFormatter.string(from: group.time)) · Logged"
    }

    private var okBar: some View {
        Button(action: onDismiss) {
            Text("OK")
                .font(DOSTypography.button)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Rectangle().fill(AmberTheme.amber))
        }
        .padding(DOSSpacing.md)
    }

    @ViewBuilder
    private func row(for marker: EventMarker) -> some View {
        let stub = entryStub(for: marker)

        HStack(alignment: .top, spacing: 10) {
            rowIcon(for: marker)
                .foregroundStyle(marker.type.color)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(primaryText(for: stub, marker: marker))
                    .font(DOSTypography.body)
                    .foregroundStyle(AmberTheme.amber)
                Text(sublineText(for: stub, marker: marker))
                    .font(DOSTypography.caption)
                    .foregroundStyle(AmberTheme.amber)
            }
            Spacer()
            Text(valueText(for: stub, marker: marker))
                .font(DOSTypography.displayMedium)
                .foregroundStyle(marker.type.color)
        }
        .padding(.horizontal, DOSSpacing.md)
        .padding(.vertical, DOSSpacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(voiceOverLabel(for: stub, marker: marker))
    }

    // MARK: - Per-row helpers

    private func entryStub(for marker: EventMarker) -> MarkerEntryStub? {
        switch marker.type {
        case .meal:
            return mealEntries.first(where: { $0.id == marker.sourceID }).map { .meal($0) }
        case .bolus, .correction, .basal:
            return insulinDeliveries.first(where: { $0.id == marker.sourceID }).map { .insulin($0) }
        case .exercise:
            return exerciseEntries.first(where: { $0.id == marker.sourceID }).map { .exercise($0) }
        }
    }

    /// Primary row text. When the entity lookup fails (rare, but possible
    /// during deletion races), fall back to a generic type label so the row
    /// still has visible content — empty Text views render as invisible
    /// blank space, hiding the bolus row entirely from the user.
    private func primaryText(for stub: MarkerEntryStub?, marker: EventMarker) -> String {
        switch stub {
        case .meal(let m): return m.mealDescription
        case .insulin(let i): return i.type.localizedDescription
        case .exercise(let e): return e.activityType
        case .none:
            switch marker.type {
            case .meal: return "Meal"
            case .bolus: return "Bolus"
            case .correction: return "Correction"
            case .basal: return "Basal"
            case .exercise: return "Exercise"
            }
        }
    }

    /// Value column. When the entity lookup fails, use the marker's
    /// pre-computed `label` — populated at chart-marker-build time from the
    /// originating entity (e.g. "5.0U" for insulin, "30g" for a meal).
    private func valueText(for stub: MarkerEntryStub?, marker: EventMarker) -> String {
        switch stub {
        case .meal(let m): return "\(Int(m.carbsGrams ?? 0))g"
        case .insulin(let i): return String(format: "%.1fU", i.units)
        case .exercise(let e): return "\(Int(e.durationMinutes))m"
        case .none: return marker.label
        }
    }

    private func sublineText(for stub: MarkerEntryStub?, marker: EventMarker) -> String {
        guard let stub else {
            // Entity not in lookup arrays — fall back to a minimal "paired"
            // hint based on the group's own composition so the row at least
            // tells the user it's part of a combined entry.
            switch marker.type {
            case .bolus, .correction, .basal:
                return group.markers.contains { $0.type == .meal } ? "paired w/ meal" : ""
            case .meal:
                return group.markers.contains { $0.type == .bolus || $0.type == .correction } ? "paired w/ insulin" : ""
            case .exercise:
                return ""
            }
        }
        let mealCount: Int
        var mealImpact: MealImpact?
        var personalFood: PersonalFoodGlycemic?
        var iob: Double?
        var confs: [ConfounderType] = []
        var paired: Bool = false

        switch stub {
        case .meal(let m):
            mealCount = group.markers.filter { $0.type == .meal }.count
            mealImpact = mealImpacts[m.id]
            personalFood = personalFoodAvgs[m.id]
            confs = confoundersFor(m)
            paired = group.markers.contains { $0.type == .bolus || $0.type == .correction }
        case .insulin(let i):
            mealCount = 1
            iob = iobAtTime(i.starts)
            paired = group.markers.contains { $0.type == .meal }
        case .exercise:
            mealCount = 1
        }

        return Self.subline(
            for: stub,
            itemCount: mealCount,
            mealImpact: mealImpact,
            personalFoodAvg: personalFood,
            glucoseUnit: glucoseUnit,
            iob: iob,
            paired: paired,
            confounders: confs
        )
    }

    @ViewBuilder
    private func rowIcon(for marker: EventMarker) -> some View {
        switch marker.type {
        case .meal:
            AppleIcon().frame(width: 20, height: 20)
        case .bolus, .correction, .basal, .exercise:
            Image(systemName: marker.type.icon)
                .font(.system(size: 20))
        }
    }

    private func voiceOverLabel(for stub: MarkerEntryStub?, marker: EventMarker) -> String {
        primaryText(for: stub, marker: marker) + ", " + valueText(for: stub, marker: marker)
    }

    // MARK: - Static testable helper

    static func subline(
        for marker: MarkerEntryStub,
        itemCount: Int,
        mealImpact: MealImpact?,
        personalFoodAvg: PersonalFoodGlycemic?,
        glucoseUnit: GlucoseUnit,
        iob: Double?,
        paired: Bool,
        confounders: [ConfounderType]
    ) -> String {
        switch marker {
        case .meal(let meal):
            var parts: [String] = []

            // IN PROGRESS within 2-hour window from meal time
            let age = -meal.timestamp.timeIntervalSinceNow
            if age >= 0 && age < 2 * 60 * 60 {
                parts.append("IN PROGRESS")
            }

            // Delta with unit conversion
            if let impact = mealImpact {
                let delta = impact.deltaMgDL
                let sign = delta >= 0 ? "+" : ""
                let formatted: String
                switch glucoseUnit {
                case .mgdL:
                    formatted = "\(sign)\(delta) mg/dL"
                case .mmolL:
                    let mmol = Double(delta) / 18.0
                    formatted = "\(sign)\(String(format: "%.1f", mmol)) mmol/L"
                }
                parts.append(formatted)
            }

            // PersonalFood avg
            if let pf = personalFoodAvg {
                let sign = pf.avgDelta >= 0 ? "+" : ""
                parts.append("avg \(sign)\(pf.avgDelta) (\(pf.observationCount))")
            }

            // Confounder summary
            if !confounders.isEmpty {
                let symbols = confounders.map { confounderSymbol(for: $0) }.joined(separator: " ")
                parts.append(symbols)
            }

            return parts.joined(separator: " · ")

        case .insulin(let insulin):
            var parts: [String] = []
            if let iob, iob > 0.05 {
                parts.append("IOB \(String(format: "%.1f", iob))U")
            }
            if paired {
                parts.append("paired w/ meal")
            }
            // Type label as fallback if nothing else
            if parts.isEmpty {
                parts.append(insulin.type.localizedDescription)
            }
            return parts.joined(separator: " · ")

        case .exercise(let exercise):
            return "\(Int(exercise.durationMinutes)) min · \(exercise.activityType)"
        }
    }

    private static func confounderSymbol(for c: ConfounderType) -> String {
        switch c {
        case .correctionBolus: return "💉"
        case .exercise: return "🏃"
        case .stackedMeal: return "🍽"
        }
    }
}
