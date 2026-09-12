//
//  LabCaption.swift
//  DOSBTS
//
//  Chart Lab (DMNC-1500 / P5): the ONE renderer for every number the lab
//  prints. Card lines, card titles and the feature sheet all go through
//  `LabCaption` — nothing in the lab interpolates a number into a string by
//  hand, which is what keeps "every figure ships with its n" true by
//  construction rather than by vigilance.
//
//  `text(for:unit:)` is pure and unit-aware; the view is a thin `Text` over it
//  so the CONTENT is pinned by tests rather than only by eye.
//

import SwiftUI

// MARK: - LabCaption

struct LabCaption: View {
    // MARK: Internal

    let items: [LabFactItem]
    let glucoseUnit: GlucoseUnit
    var font: Font = DOSTypography.label
    var color: Color = AmberTheme.amber

    init(
        items: [LabFactItem],
        glucoseUnit: GlucoseUnit,
        font: Font = DOSTypography.label,
        color: Color = AmberTheme.amber
    ) {
        self.items = items
        self.glucoseUnit = glucoseUnit
        self.font = font
        self.color = color
    }

    init(
        figure: LabFigure,
        glucoseUnit: GlucoseUnit,
        font: Font = DOSTypography.label,
        color: Color = AmberTheme.amber
    ) {
        self.init(items: [.figure(figure)], glucoseUnit: glucoseUnit, font: font, color: color)
    }

    var body: some View {
        Text(Self.text(for: items, unit: glucoseUnit))
            .font(font)
            .foregroundStyle(color)
            .monospacedDigit()
            // One line that scales as a whole: an HStack of Texts truncates its
            // children individually, and the part that vanishes is usually the
            // `n=` — the one thing the lab may never drop (P0's readout bug).
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    // MARK: Pure rendering

    /// `" · "` — the DOS separator between items on a line.
    static let separator = " · "

    /// "No data." Never a zero: a zero is a measurement.
    static let noData = "—"

    static func text(for items: [LabFactItem], unit: GlucoseUnit) -> String {
        items.map { text(for: $0, unit: unit) }.joined(separator: separator)
    }

    static func text(for item: LabFactItem, unit: GlucoseUnit) -> String {
        switch item {
        case .figure(let figure):
            return text(for: figure, unit: unit)
        case .observation(let label, let value, let n):
            // No record behind it → an em dash, whatever the value says.
            guard n > 0 else { return "\(label) \(noData)" }
            guard let value, !value.isEmpty else { return label }
            return "\(label) \(value)"
        }
    }

    static func text(for figure: LabFigure, unit: GlucoseUnit) -> String {
        guard figure.n > 0 || figure.kind.printsAtZeroSampleSize else {
            return join(figure.label, noData)
        }

        var core = core(for: figure, unit: unit)

        if let spread = figure.spread, figure.kind != .band {
            core += " (\(number(spread.lowerBound, kind: figure.kind, unit: unit))–\(number(spread.upperBound, kind: figure.kind, unit: unit)))"
        }

        let labelled = join(figure.label, core)
        return figure.citesSampleSize ? "\(labelled)\(separator)n=\(figure.n)" : labelled
    }

    // MARK: Private

    private static func join(_ label: String?, _ core: String) -> String {
        guard let label, !label.isEmpty else { return core }
        return "\(label) \(core)"
    }

    /// The number plus its suffix. Units that read as a suffix (`U`, `g`) hug
    /// the number the way the hero's IOB label does; word units and glucose
    /// units take a space.
    private static func core(for figure: LabFigure, unit: GlucoseUnit) -> String {
        let value = number(figure.value, kind: figure.kind, unit: unit)

        switch figure.kind {
        case .band:
            guard let spread = figure.spread else { return value }
            return "\(number(spread.lowerBound, kind: figure.kind, unit: unit))–\(number(spread.upperBound, kind: figure.kind, unit: unit))"
        case .sampleCount:
            return suffixed("n=\(Int(figure.value.rounded()))", figure.displayUnit(for: unit))
        default:
            return suffixed(value, figure.displayUnit(for: unit))
        }
    }

    private static func suffixed(_ value: String, _ unit: String) -> String {
        guard !unit.isEmpty else { return value }
        return isTightUnit(unit) ? "\(value)\(unit)" : "\(value) \(unit)"
    }

    /// `1.8U`, `60g` — no space, matching `GlucoseView.formatIOB` and the meal
    /// rows. Everything else (`MIN`, `RDG`, `mg/dL`) takes one.
    private static func isTightUnit(_ unit: String) -> Bool {
        unit == "U" || unit == "g"
    }

    private static func number(_ value: Double, kind: LabFigure.Kind, unit: GlucoseUnit) -> String {
        switch kind {
        case .glucose, .median, .percentile, .band:
            return glucose(value, unit: unit)
        case .delta:
            let formatted = glucose(value, unit: unit)
            return value > 0 ? "+\(formatted)" : formatted
        case .iob, .insulin:
            return String(format: "%.1f", value)
        case .peakMinutes, .cob, .carbs, .count, .sampleCount, .duration:
            return "\(Int(value.rounded()))"
        }
    }

    /// mg/dL in, display unit out — converted exactly once, then formatted with
    /// the same formatters `Int.asGlucose` uses internally.
    private static func glucose(_ mgdL: Double, unit: GlucoseUnit) -> String {
        if unit == .mmolL {
            return GlucoseFormatters.mmolLFormatter.string(from: mgdL.toMmolL() as NSNumber) ?? noData
        }
        return GlucoseFormatters.mgdLFormatter.string(from: mgdL as NSNumber) ?? noData
    }
}

// MARK: - Display unit suffix

extension LabFigure {
    /// The unit string a glucose-family figure should print, once the user's
    /// display unit is known. A non-empty stored unit means "print a unit here";
    /// WHICH unit is the user's business, never the engine's.
    func displayUnit(for glucoseUnit: GlucoseUnit) -> String {
        guard kind.isGlucoseFamily, !unit.isEmpty else { return unit }
        return glucoseUnit.localizedDescription
    }
}
