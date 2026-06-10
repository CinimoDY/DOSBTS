//
//  LoggedMealToast.swift
//  DOSBTS
//
//  Confirmation toast for quick-logged meals (DMNC-796). Extracted from
//  UnifiedFoodEntryView; shape and timing preserved (bottom overlay, 3s
//  auto-dismiss, UNDO). The caller owns the logged MealEntry and the undo
//  side effect — the toast never dispatches deletes itself, so the UNDO
//  reference always carries the UUID the caller persisted.
//

import SwiftUI

// MARK: - LoggedMealToast

struct LoggedMealToast: View {
    let meal: MealEntry
    let onUndo: () -> Void

    var body: some View {
        HStack {
            Text("Logged: \(meal.mealDescription)")
                .font(DOSTypography.caption)
                .foregroundColor(AmberTheme.amber)
                .lineLimit(1)

            Spacer()

            Button("UNDO", action: onUndo)
                .font(DOSTypography.caption)
                .foregroundColor(AmberTheme.cgaGreen)
        }
        .padding(DOSSpacing.sm)
        .background(Color.black.opacity(0.95))
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(AmberTheme.amberDark, lineWidth: 1)
        )
        .padding(.horizontal, DOSSpacing.md)
        .padding(.bottom, DOSSpacing.md)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - LoggedMealToastController

/// Show/dismiss lifecycle for the toast: 3s auto-dismiss, re-show replaces
/// content and resets the timer. Publishes state only — the presenting view
/// owns the animation (`.animation(_:value:)` on the overlay).
@MainActor
final class LoggedMealToastController: ObservableObject {
    static let autoDismissDelay: TimeInterval = 3.0

    @Published private(set) var meal: MealEntry?

    private var workItem: DispatchWorkItem?

    func show(_ meal: MealEntry) {
        self.meal = meal
        workItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.dismiss() }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoDismissDelay, execute: item)
    }

    func dismiss() {
        workItem?.cancel()
        workItem = nil
        meal = nil
    }
}
