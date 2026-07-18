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

    // Batch staging (DMNC-1413): entries queued via STAGE ENTRY, committed all
    // at once on CONFIRM. See `InsulinBatchBuilder` for the pure commit-set /
    // staged-IOB rules this view delegates to.
    @State private var staged: [InsulinDelivery] = []
    @State private var showDiscardConfirm = false
    // Reentrancy guard: a rapid double-tap on CONFIRM during the dismiss
    // animation would dispatch the batch twice — and because the current-form
    // entry gets a fresh UUID per commitSet evaluation, the second dispatch
    // would create a genuine duplicate dose record that batch-UNDO couldn't
    // fully remove. First tap wins; everything after is a no-op.
    @State private var didConfirm = false

    var addCallback: (_ deliveries: [InsulinDelivery]) -> Void

    private var currentIOB: Double {
        // Stacking warning for correction boluses considers only rapid-acting
        // (meal/snack/correction) IOB — not basal. A user adding a correction
        // is reasoning about how much *fast* insulin is already on board to
        // bring glucose down; long-acting basal is the steady-state baseline
        // and isn't part of the correction-stacking decision.
        //
        // Staged-but-not-yet-committed entries count too: a user who staged a
        // snack bolus and is now considering a correction bolus needs the
        // warning to reflect the snack, not just what's already in the DB.
        let bolusModel = ExponentialInsulinModel.bolus(preset: store.state.bolusInsulinPreset)
        let basalModel = ExponentialInsulinModel.basal(diaMinutes: store.state.basalDIAMinutes)
        return computeIOB(
            deliveries: InsulinBatchBuilder.iobInputs(committed: store.state.iobDeliveries, staged: staged),
            bolusModel: bolusModel,
            basalModel: basalModel
        ).mealSnackIOB
    }

    /// The full set CONFIRM will commit: staged entries plus the current form
    /// if it holds a valid (units > 0) entry the user never staged.
    private var commitSet: [InsulinDelivery] {
        InsulinBatchBuilder.commitSet(
            staged: staged,
            currentUnits: units,
            currentType: insulinType,
            starts: starts,
            ends: ends
        )
    }

    private var confirmLabel: String {
        let count = commitSet.count
        return count > 1 ? "CONFIRM \(count)" : "CONFIRM"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DOSSpacing.lg) {
                    typeRow
                    unitsRow

                    // Surface the Ratio Lab reference ICR (if the user has saved one)
                    // at the moment it's educationally relevant — carb-bolus entry.
                    // Display-only: never computes units, reads the entered value,
                    // or suggests a dose. Hidden for correction/basal (ICR-irrelevant).
                    if let confirmedICR = store.state.confirmedICR,
                       insulinType == .mealBolus || insulinType == .snackBolus {
                        referenceRatioLine(confirmedICR)
                    }

                    timeRow

                    if insulinType == .basal {
                        endsRow
                    }

                    if insulinType == .correctionBolus, currentIOB > 0.05 {
                        iobWarning
                    }

                    if (units ?? 0) > 0 {
                        stageEntryButton
                    }

                    if !staged.isEmpty {
                        stagedSection
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
                    Button("Cancel", role: .cancel) { cancel() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(confirmLabel) { confirm() }
                        .disabled(commitSet.isEmpty)
                        .foregroundStyle(commitSet.isEmpty ? AmberTheme.borderSubtle : AmberTheme.amber)
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
            .confirmationDialog(
                staged.count.pluralizeLocalization(
                    singular: "Discard %@ staged entry?",
                    plural: "Discard %@ staged entries?"
                ),
                isPresented: $showDiscardConfirm,
                titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
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

    // Passive reference-ratio line: the confirmed Ratio Lab ICR, styled as
    // information (dim amberDark + surfaceTint fill), NOT a warning like iobWarning.
    // No tap action, no math against the entered units — deliberately non-imperative.
    private func referenceRatioLine(_ icr: Double) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "function")
                .foregroundStyle(AmberTheme.amberDark)
                .frame(height: 14)
            Text("REF RATIO \(RatioEstimator.icrLabel(icr)) — SET IN RATIO LAB")
                .font(DOSTypography.caption)
                .foregroundStyle(AmberTheme.amberDark)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AmberTheme.surfaceTint)
        .overlay(
            Rectangle()
                .stroke(AmberTheme.borderSubtle, lineWidth: 1)
        )
    }

    private var stageEntryButton: some View {
        Button("STAGE ENTRY") { stageCurrentEntry() }
            .buttonStyle(.dosGhost)
            .frame(maxWidth: .infinity)
    }

    private var stagedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STAGED · \(staged.count)")
                .dosHeader()
            VStack(spacing: DOSSpacing.xs) {
                ForEach(staged) { entry in
                    stagedRow(entry)
                }
            }
        }
    }

    // In-place editing of a staged row is out of scope for V1 — remove + re-enter.
    private func stagedRow(_ entry: InsulinDelivery) -> some View {
        HStack(spacing: 8) {
            Text(entry.type.shortLabel)
                .font(DOSTypography.caption)
                .foregroundStyle(AmberTheme.amber)
            Text(entry.units.asInsulinUnits())
                .font(DOSTypography.caption)
                .foregroundStyle(AmberTheme.amber)
            Spacer()
            Text(entry.starts.toLocalTime())
                .font(DOSTypography.caption)
                .foregroundStyle(AmberTheme.amberDark)
            Button {
                staged.removeAll { $0.id == entry.id }
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(AmberTheme.amberDark)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove staged \(entry.units.asInsulinUnits()) \(entry.type.localizedDescription)")
        }
        .dosCard(.stat, padding: DOSSpacing.sm)
    }

    // MARK: - Actions

    private func stageCurrentEntry() {
        guard let u = units, u > 0 else { return }
        // Shared basal-ends rule lives in makeEntry — same helper commitSet
        // uses, so the staging and commit paths can't drift apart.
        staged.append(InsulinBatchBuilder.makeEntry(units: u, type: insulinType, starts: starts, ends: ends))
        // Clear units only — type and time selections persist for the next entry.
        units = nil
    }

    private func confirm() {
        guard !didConfirm else { return }
        let deliveries = commitSet
        guard !deliveries.isEmpty else { return }
        didConfirm = true
        addCallback(deliveries)
        dismiss()
    }

    private func cancel() {
        if staged.isEmpty {
            dismiss()
        } else {
            showDiscardConfirm = true
        }
    }
}

struct AddInsulinView_Previews: PreviewProvider {
    static var previews: some View {
        Button("Modal always shown") {}
            .sheet(isPresented: .constant(true)) {
                AddInsulinView(addCallback: { _ in })
                    .environmentObject(DirectStore(initialState: AppState(), reducer: directReducer, middlewares: []))
            }
    }
}
