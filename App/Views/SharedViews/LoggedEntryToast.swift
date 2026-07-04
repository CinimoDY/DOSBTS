//
//  LoggedEntryToast.swift
//  DOSBTS
//
//  Generalised log-confirmation toast (DMNC-1294). Covers manual meal,
//  insulin, and blood glucose paths where the entry sheet closes on log.
//  Quick-log paths (favorites/recents) keep their in-sheet LoggedMealToast.
//
//  Usage pattern:
//    1. In the log callback (before dismiss): loggedEntryToast.stage(.insulin(d))
//    2. In ContentView's sheet onDismiss: loggedEntryToast.showStagedIfAny()
//    3. ContentView overlay renders LoggedEntryToastView and dispatches UNDO.
//

import SwiftUI

// MARK: - LoggedEntry

enum LoggedEntry: Equatable {
    case meal(MealEntry)
    case insulin(InsulinDelivery)
    case bloodGlucose(BloodGlucose)

    var entryID: UUID {
        switch self {
        case .meal(let m): return m.id
        case .insulin(let i): return i.id
        case .bloodGlucose(let g): return g.id
        }
    }

    func label(glucoseUnit: GlucoseUnit) -> String {
        switch self {
        case .meal(let m):
            return "Logged: \(m.mealDescription)"
        case .insulin(let i):
            let unitStr = i.units.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(i.units))U" : String(format: "%.1fU", i.units)
            return "Logged: \(unitStr) \(i.type.description)"
        case .bloodGlucose(let g):
            if glucoseUnit == .mmolL {
                let mmol = Double(g.glucoseValue) * GlucoseUnit.exchangeRate
                return String(format: "Logged: BG %.1f mmol/L", mmol)
            } else {
                return "Logged: BG \(g.glucoseValue) mg/dL"
            }
        }
    }
}

// MARK: - LoggedEntryToastView

struct LoggedEntryToastView: View {
    let label: String
    let onUndo: () -> Void

    var body: some View {
        HStack {
            Text(label)
                .font(DOSTypography.caption)
                .foregroundStyle(AmberTheme.amber)
                .lineLimit(1)

            Spacer()

            Button("UNDO", action: onUndo)
                .font(DOSTypography.caption)
                .foregroundStyle(AmberTheme.cgaGreen)
        }
        .dosCard(.toast, stroke: AmberTheme.amberDark, padding: DOSSpacing.sm)
        .padding(.horizontal, DOSSpacing.md)
        .padding(.bottom, DOSSpacing.md)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - LoggedEntryToastController

/// Show/dismiss lifecycle for the post-dismiss confirmation toast.
///
/// Stage an entry during the log callback (before the sheet dismisses), then
/// call `showStagedIfAny()` from the sheet's `onDismiss` to surface it once
/// the sheet is fully gone. Re-staging before `showStagedIfAny()` replaces
/// the pending entry; re-showing while active resets the auto-dismiss timer.
@MainActor
final class LoggedEntryToastController: ObservableObject {
    static let autoDismissDelay: TimeInterval = 3.0

    @Published private(set) var active: LoggedEntry?

    private var staged: LoggedEntry?
    private var workItem: DispatchWorkItem?

    func stage(_ entry: LoggedEntry) {
        staged = entry
    }

    func showStagedIfAny() {
        guard let entry = staged else { return }
        staged = nil
        show(entry)
    }

    func show(_ entry: LoggedEntry) {
        active = entry
        workItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.dismiss() }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoDismissDelay, execute: item)
    }

    func dismiss() {
        workItem?.cancel()
        workItem = nil
        active = nil
    }
}
