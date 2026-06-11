//
//  MealItemRow.swift
//  DOSBTS
//
//  Shared meal-item component (R3): one component with documented
//  per-context variants replaces the bespoke rows in the food-entry
//  recents list and the Lists tab. Variants are intentionally not
//  pixel-identical — each context keeps its own layout, but layout,
//  type scale, color roles, and affordances live in one place.
//

import SwiftUI

// MARK: - Display model (unit-tested)

/// Pure derivation of what a meal row shows per variant. The view renders
/// this verbatim; tests pin the mapping without view inspection.
struct MealItemDisplayModel: Equatable {
    let name: String
    /// "25g carbs" — nil when the meal has no carbs value.
    let carbsLabel: String?
    /// Local date+time — `.list` variant only.
    let timestampLabel: String?
    /// "12g P" / "8g F" / "320 kcal" — `.list` variant only, omits nils.
    let macroLabels: [String]

    init(meal: MealEntry, variant: MealItemRow.Variant) {
        // Never clipped here: truncation is a rendering concern
        // (lineLimit + tail in the view); the label keeps the full string.
        name = meal.mealDescription
        carbsLabel = meal.carbsGrams.map { "\(Int($0))g carbs" }

        switch variant {
        case .recent:
            timestampLabel = nil
            macroLabels = []
        case .list:
            timestampLabel = meal.timestamp.toLocalDateTime()
            var macros: [String] = []
            if let p = meal.proteinGrams { macros.append("\(Int(p))g P") }
            if let f = meal.fatGrams { macros.append("\(Int(f))g F") }
            if let cal = meal.calories { macros.append("\(Int(cal)) kcal") }
            macroLabels = macros
        }
    }
}

// MARK: - MealItemRow

/// Documented variants:
/// - `.recent` — compact single line (`> name … carbs`). Rides inside
///   `HoldToCommitProgress`, so it attaches NO affordances of its own:
///   a context menu can't coexist with the hold recognizer (DMNC-796
///   KTD-3), and swipe actions must hang off the hold wrapper at the
///   call site to reliably reach the List row. Callers own them.
/// - `.list` — two-line detail row (timestamp + name, carbs + macros).
///   Attaches leading swipe (log again), trailing swipe (delete +
///   favorite), and a context menu from whichever callbacks are supplied.
///
/// Affordances are caller-supplied, never baked in: a context that omits
/// a callback simply doesn't get that affordance.
struct MealItemRow: View {
    enum Variant {
        case recent
        case list
    }

    let meal: MealEntry
    let variant: Variant
    var onLogAgain: (() -> Void)? = nil
    var onAddToFavorite: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    private var model: MealItemDisplayModel {
        MealItemDisplayModel(meal: meal, variant: variant)
    }

    var body: some View {
        switch variant {
        case .recent:
            // Bare content: the caller wraps this in HoldToCommitProgress
            // and attaches swipe affordances on that wrapper.
            content

        case .list:
            content
                .swipeActions(edge: .leading) {
                    if let onLogAgain {
                        Button {
                            onLogAgain()
                        } label: {
                            Label("Log Again", systemImage: "arrow.counterclockwise")
                        }
                        .tint(AmberTheme.cgaGreen)
                    }
                }
                .swipeActions(edge: .trailing) {
                    if let onDelete {
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    if let onAddToFavorite {
                        Button {
                            onAddToFavorite()
                        } label: {
                            Label("Add to Favorites", systemImage: "star")
                        }
                        .tint(AmberTheme.amber)
                    }
                }
                .modifier(ListContextMenu(
                    onLogAgain: onLogAgain,
                    onAddToFavorite: onAddToFavorite,
                    onDelete: onDelete
                ))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch variant {
        case .recent:
            HStack {
                // Deliberately dim: the prompt glyph is a decorative DOS
                // affordance, not informational text — it stays amberDark
                // even though section headers migrated to amber (R5 audit).
                Text("> ")
                    .font(DOSTypography.bodySmall)
                    .foregroundColor(AmberTheme.amberDark)

                Text(model.name)
                    .font(DOSTypography.bodySmall)
                    .foregroundColor(AmberTheme.amber)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                if let carbsLabel = model.carbsLabel {
                    Text(carbsLabel)
                        .font(DOSTypography.caption)
                        .foregroundColor(AmberTheme.amber)
                }
            }
            .frame(minHeight: 44)

        case .list:
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let timestampLabel = model.timestampLabel {
                        Text(verbatim: timestampLabel)
                            .monospacedDigit()
                    }

                    Text(verbatim: model.name)
                        .opacity(0.5)
                        .font(DOSTypography.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if let carbsLabel = model.carbsLabel {
                        Text(verbatim: carbsLabel)
                            .monospacedDigit()
                    }

                    if !model.macroLabels.isEmpty {
                        HStack(spacing: DOSSpacing.xs) {
                            ForEach(model.macroLabels, id: \.self) { macro in
                                Text(verbatim: macro)
                            }
                        }
                        .font(DOSTypography.caption)
                        .foregroundStyle(AmberTheme.amber)
                    }
                }
            }
            .frame(minHeight: 44)
        }
    }
}

// MARK: - List context menu

/// `.list`-only: the menu attaches when any callback is supplied.
private struct ListContextMenu: ViewModifier {
    let onLogAgain: (() -> Void)?
    let onAddToFavorite: (() -> Void)?
    let onDelete: (() -> Void)?

    func body(content: Content) -> some View {
        if onLogAgain != nil || onAddToFavorite != nil || onDelete != nil {
            content.contextMenu {
                if let onLogAgain {
                    Button {
                        onLogAgain()
                    } label: {
                        Label("Log Again", systemImage: "arrow.counterclockwise")
                    }
                }

                if let onAddToFavorite {
                    Button {
                        onAddToFavorite()
                    } label: {
                        Label("Add to Favorites", systemImage: "star")
                    }
                }

                if let onDelete {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        } else {
            content
        }
    }
}
