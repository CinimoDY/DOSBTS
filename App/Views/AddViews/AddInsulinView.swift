//
//  AddInsulinView.swift
//  DOSBTSApp
//

import SwiftUI

struct AddInsulinView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: DirectStore

    @State var starts: Date = .init()
    @State var ends: Date = .init()
    @State var units: Double?
    @State var insulinType: InsulinType = .snackBolus

    var addCallback: (_ starts: Date, _ ends: Date, _ units: Double, _ insulinType: InsulinType) -> Void

    private var currentIOB: Double {
        // Stacking warning for correction boluses considers only rapid-acting
        // (meal/snack/correction) IOB — not basal. A user adding a correction
        // is reasoning about how much *fast* insulin is already on board to
        // bring glucose down; long-acting basal is the steady-state baseline
        // and isn't part of the correction-stacking decision.
        let bolusModel = ExponentialInsulinModel.bolus(preset: store.state.bolusInsulinPreset)
        let basalModel = ExponentialInsulinModel.basal(diaMinutes: store.state.basalDIAMinutes)
        return computeIOB(
            deliveries: store.state.iobDeliveries,
            bolusModel: bolusModel,
            basalModel: basalModel
        ).mealSnackIOB
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DOSSpacing.lg) {
                    typeRow
                    unitsRow
                    timeRow

                    if insulinType == .basal {
                        endsRow
                    }

                    if insulinType == .correctionBolus, currentIOB > 0.05 {
                        iobWarning
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AmberTheme.dosBlack.ignoresSafeArea())
            .dosNavigationTitle("Insulin")
            .navigationBarBackButtonHidden(true)
            // Prevent swipe-dismiss so half-entered data isn't silently discarded.
            .interactiveDismissDisabled()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") { save() }
                        .disabled((units ?? 0) <= 0)
                        .foregroundStyle((units ?? 0) > 0 ? AmberTheme.amber : AmberTheme.borderSubtle)
                }
            }
            // Auto-set ENDS to 24 hours after STARTS for basal entries — once-daily
            // injections (Tresiba/Lantus/Levemir) are the dominant case and saving
            // the manual date+time picker click on every entry is a meaningful win.
            // Triggers when the user picks .basal as the type AND when they adjust
            // the starts time while basal is selected.
            .onChange(of: insulinType) { _, newType in
                if newType == .basal {
                    ends = Calendar.current.date(byAdding: .hour, value: 24, to: starts) ?? starts.addingTimeInterval(24 * 60 * 60)
                }
            }
            .onChange(of: starts) { _, newStarts in
                if insulinType == .basal {
                    ends = Calendar.current.date(byAdding: .hour, value: 24, to: newStarts) ?? newStarts.addingTimeInterval(24 * 60 * 60)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Form rows

    private func formLabel(_ text: String) -> some View {
        Text(text)
            .font(DOSTypography.microLabel)
            .tracking(0.6)
            .foregroundStyle(AmberTheme.amber)
    }

    private var typeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            formLabel("TYPE")
            HStack(spacing: DOSSpacing.xxs) {
                ForEach(InsulinType.allCases, id: \.self) { type in
                    AmberChip(
                        label: type.shortLabel,
                        variant: .type,
                        tint: AmberTheme.amber,
                        isSelected: insulinType == type,
                        action: { insulinType = type }
                    )
                }
            }
        }
    }

    private var unitsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            formLabel("UNITS")
            StepperField(
                title: "Units",
                value: $units,
                step: 1.0,
                range: 0...50,
                unit: "U",
                helpText: "tap value to type · ±1U steps"
            )
        }
    }

    private var timeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            formLabel(insulinType == .basal ? "STARTS" : "TIME")
            QuickTimeChips(title: "Time", date: $starts)
        }
    }

    private var endsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            formLabel("ENDS")
            DatePicker("", selection: $ends, displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(AmberTheme.amber)
        }
    }

    private var iobWarning: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AmberTheme.amber)
            Text("ACTIVE IOB: \(String(format: "%.1f", currentIOB))U")
                .font(DOSTypography.caption)
                .foregroundStyle(AmberTheme.amber)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AmberTheme.amber.opacity(0.08))
        .overlay(
            Rectangle()
                .stroke(AmberTheme.amber.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Save

    private func save() {
        guard let u = units, u > 0 else { return }
        let endsTime = insulinType == .basal ? ends : starts
        addCallback(starts, endsTime, u, insulinType)
        dismiss()
    }
}

struct AddInsulinView_Previews: PreviewProvider {
    static var previews: some View {
        Button("Modal always shown") {}
            .sheet(isPresented: .constant(true)) {
                AddInsulinView(addCallback: { _, _, _, _ in })
                    .environmentObject(DirectStore(initialState: AppState(), reducer: directReducer, middlewares: []))
            }
    }
}
