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
    /// Tapping a meal/insulin row edits just that entry — routed through the
    /// SheetCoordinator's dismiss-then-present at the call site (never a nested
    /// sheet). Exercise rows are read-only and never invoke this.
    let onEditEntry: (EventMarker) -> Void
    /// Swipe-delete of a single entry. The caller dispatches the mapped
    /// whole-record delete; the overlay removes the row locally.
    let onDeleteEntry: (EventMarker) -> Void
    let onDismiss: () -> Void

    /// Chronological rows, held locally so a swipe-delete animates one entry out
    /// immediately (and the sheet can self-dismiss when the last row goes)
    /// without waiting for a full state round-trip.
    @State private var markers: [EventMarker]

    init(
        group: ConsolidatedMarkerGroup,
        mealEntries: [MealEntry],
        insulinDeliveries: [InsulinDelivery],
        exerciseEntries: [ExerciseEntry],
        mealImpacts: [UUID: MealImpact],
        personalFoodAvgs: [UUID: PersonalFoodGlycemic],
        glucoseUnit: GlucoseUnit,
        iobAtTime: @escaping (Date) -> Double?,
        confoundersFor: @escaping (MealEntry) -> [ConfounderType],
        onEditEntry: @escaping (EventMarker) -> Void,
        onDeleteEntry: @escaping (EventMarker) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.group = group
        self.mealEntries = mealEntries
        self.insulinDeliveries = insulinDeliveries
        self.exerciseEntries = exerciseEntries
        self.mealImpacts = mealImpacts
        self.personalFoodAvgs = personalFoodAvgs
        self.glucoseUnit = glucoseUnit
        self.iobAtTime = iobAtTime
        self.confoundersFor = confoundersFor
        self.onEditEntry = onEditEntry
        self.onDeleteEntry = onDeleteEntry
        self.onDismiss = onDismiss
        _markers = State(initialValue: group.markers.sorted { $0.time < $1.time })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(AmberTheme.amberDark)
            entryList
        }
        .safeAreaInset(edge: .bottom) { okBar }
        .background(AmberTheme.dosBlack.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    // `.swipeActions` requires a `List` row — so the rows region is a plain,
    // background-free List styled to keep the DOS look: black rows, amber
    // separators. Header stays above the List; okBar stays in the bottom inset.
    private var entryList: some View {
        List {
            ForEach(markers) { marker in
                row(for: marker)
                    .listRowBackground(AmberTheme.dosBlack)
                    .listRowInsets(EdgeInsets(
                        top: DOSSpacing.sm,
                        leading: DOSSpacing.md,
                        bottom: DOSSpacing.sm,
                        trailing: DOSSpacing.md
                    ))
                    .listRowSeparatorTint(AmberTheme.borderSubtle)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deleteRow(marker)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func deleteRow(_ marker: EventMarker) {
        onDeleteEntry(marker)
        markers.removeAll { $0.id == marker.id }
        if markers.isEmpty {
            onDismiss()
        }
    }

    private var header: some View {
        HStack {
            Text(headerText)
                .font(DOSTypography.body)
                .foregroundStyle(AmberTheme.amber)
            Spacer()
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
                .foregroundStyle(AmberTheme.inkOnAmber)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Rectangle().fill(AmberTheme.amber))
        }
        .padding(DOSSpacing.md)
    }

    @ViewBuilder
    private func row(for marker: EventMarker) -> some View {
        let stub = entryStub(for: marker)
        // Editable requires both an editable TYPE and a resolvable entity —
        // during a deletion race the row falls back to stub-nil rendering, and
        // tapping through would open an empty dead-end editor. No entity, no
        // chevron, no tap.
        let editable = Self.isEditable(marker.type) && stub != nil
        let time = rowTime(for: marker, stub: stub)
        let subline = sublineText(for: stub, marker: marker)

        HStack(alignment: .top, spacing: 10) {
            rowIcon(for: marker)
                .foregroundStyle(marker.type.color)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(primaryText(for: stub, marker: marker))
                    .font(DOSTypography.body)
                    .foregroundStyle(AmberTheme.amber)
                if !subline.isEmpty {
                    Text(subline)
                        .font(DOSTypography.caption)
                        .foregroundStyle(AmberTheme.amber)
                }
            }
            Spacer()
            // Value on top, this entry's own logged time beneath it — placed
            // identically for every row type (meal / insulin / exercise).
            VStack(alignment: .trailing, spacing: 2) {
                Text(valueText(for: stub, marker: marker))
                    .font(DOSTypography.displayMedium)
                    .foregroundStyle(marker.type.color)
                Text(time)
                    .font(DOSTypography.caption)
                    .foregroundStyle(AmberTheme.amberDark)
            }
            // Chevron only on editable (meal/insulin) rows — exercise is read-only.
            if editable {
                Image(systemName: "chevron.right")
                    .font(DOSTypography.caption)
                    .foregroundStyle(AmberTheme.amberDark)
                    .padding(.top, 4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if editable { onEditEntry(marker) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(voiceOverLabel(for: stub, marker: marker, time: time))
        .accessibilityAddTraits(editable ? .isButton : [])
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
                .font(DOSTypography.bodyLarge)
        }
    }

    private func voiceOverLabel(for stub: MarkerEntryStub?, marker: EventMarker, time: String) -> String {
        primaryText(for: stub, marker: marker) + ", " + valueText(for: stub, marker: marker) + ", " + time
    }

    /// Instance convenience: extracts the insulin (if any) from the stub, then
    /// defers to the static `rowTime` so the time logic stays unit-testable.
    private func rowTime(for marker: EventMarker, stub: MarkerEntryStub?) -> String {
        if case .insulin(let i) = stub {
            return Self.rowTime(for: marker, insulin: i)
        }
        return Self.rowTime(for: marker, insulin: nil)
    }

    // MARK: - Static testable helpers

    /// A row's own logged time as `HH:mm`. Insulin rows read the delivery's
    /// `starts`; every other type reads the marker's `time`.
    static func rowTime(for marker: EventMarker, insulin: InsulinDelivery?) -> String {
        let date: Date
        switch marker.type {
        case .bolus, .correction, .basal:
            date = insulin?.starts ?? marker.time
        case .meal, .exercise:
            date = marker.time
        }
        return headerTimeFormatter.string(from: date)
    }

    /// Whether tapping a row can open the combined editor. Exercise is read-only
    /// (the editor cannot edit exercise), so only meal + insulin rows are
    /// editable.
    static func isEditable(_ type: EventMarkerType) -> Bool {
        switch type {
        case .meal, .bolus, .correction, .basal: return true
        case .exercise: return false
        }
    }

    /// Which whole-record delete a row of this type maps to. Pure so the routing
    /// is testable without constructing entities or a store.
    enum MarkerDeleteKind: Equatable {
        case meal
        case insulin
        case exercise
    }

    static func deleteKind(for type: EventMarkerType) -> MarkerDeleteKind {
        switch type {
        case .meal: return .meal
        case .bolus, .correction, .basal: return .insulin
        case .exercise: return .exercise
        }
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
