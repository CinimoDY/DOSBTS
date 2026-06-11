//
//  TreatmentModalView.swift
//  DOSBTS
//

import SwiftUI

struct TreatmentModalView: View {
    @EnvironmentObject var store: DirectStore
    @Environment(\.dismiss) var dismiss

    let alarmFiredAt: Date
    let onMoreTapped: () -> Void

    @State private var overrideTimestamp: Date = .init()
    @State private var showTimePicker = false

    private var defaultFavorite: FavoriteFood? {
        store.state.favoriteFoodValues
            .filter(\.isHypoTreatment)
            .sorted(by: { $0.sortOrder < $1.sortOrder })
            .first
    }

    private var timeSinceAlarm: TimeInterval {
        Date().timeIntervalSince(alarmFiredAt)
    }

    private var needsTimestampNudge: Bool {
        timeSinceAlarm > 5 * 60 // >5 minutes
    }

    // MARK: - Result mode (still-low recheck)

    var isRecheckMode: Bool = false
    var recheckGlucoseValue: Int = 0

    var body: some View {
        NavigationView {
            VStack(spacing: DOSSpacing.lg) {
                Spacer()

                // Glucose display
                glucoseHeader

                // Timestamp nudge (if >5 min since alarm)
                if needsTimestampNudge && !isRecheckMode {
                    timestampNudge
                }

                Spacer()

                // Action buttons
                actionButtons

                Spacer()
            }
            .padding(.horizontal, DOSSpacing.lg)
            .background(AmberTheme.dosBlack)
            .dosNavigationTitle(isRecheckMode ? "RECHECK" : "LOW GLUCOSE")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Dismiss") {
                        if isRecheckMode {
                            store.dispatch(.endTreatmentCycle)
                        }
                        dismiss()
                    }
                    .font(DOSTypography.caption)
                    .foregroundColor(AmberTheme.amberDark)
                }
            }
        }
        .onDisappear {
            // Handle swipe-to-dismiss: clean up cycle state if recheck modal dismissed without treating
            if isRecheckMode, store.state.recheckDispatched, store.state.treatmentCycleActive {
                store.dispatch(.dismissTreatmentCycle)
            }
        }
    }

    // MARK: - Glucose Header

    @ViewBuilder
    private var glucoseHeader: some View {
        VStack(spacing: DOSSpacing.sm) {
            if isRecheckMode {
                Text("STILL LOW")
                    .font(DOSTypography.displayMedium)
                    .foregroundColor(AmberTheme.cgaRed)

                Text("\(recheckGlucoseValue) \(store.state.glucoseUnit.localizedDescription)")
                    .font(DOSTypography.glucoseHero)
                    .foregroundColor(AmberTheme.cgaRed)

                Text("Treat again?")
                    .font(DOSTypography.body)
                    .foregroundColor(AmberTheme.amber)
            } else {
                Text("LOW GLUCOSE DETECTED")
                    .font(DOSTypography.displayMedium)
                    .foregroundColor(AmberTheme.cgaRed)

                if let glucose = store.state.latestSensorGlucose {
                    Text("\(glucose.glucoseValue) \(store.state.glucoseUnit.localizedDescription)")
                        .font(DOSTypography.glucoseHero)
                        .foregroundColor(AmberTheme.cgaRed)
                }
            }
        }
    }

    // MARK: - Timestamp Nudge

    @ViewBuilder
    private var timestampNudge: some View {
        VStack(spacing: DOSSpacing.xs) {
            Text("When did you take this?")
                .font(DOSTypography.caption)
                .foregroundColor(AmberTheme.amber)

            if showTimePicker {
                DatePicker(
                    "",
                    selection: $overrideTimestamp,
                    displayedComponents: [.hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.wheel)
            }

            Button(showTimePicker ? "Confirm" : "Just now") {
                if showTimePicker {
                    showTimePicker = false
                } else {
                    // "Just now" = use current time, no override
                    overrideTimestamp = Date()
                }
            }
            .font(DOSTypography.caption)
            .foregroundColor(AmberTheme.cgaCyan)

            if !showTimePicker {
                Button("Pick a time") {
                    showTimePicker = true
                }
                .font(DOSTypography.caption)
                .foregroundColor(AmberTheme.amberDark)
            }
        }
        .padding(DOSSpacing.sm)
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: DOSSpacing.sm) {
            if let favorite = defaultFavorite {
                // Primary: Treat now
                Button(action: {
                    let timestamp = needsTimestampNudge && showTimePicker ? overrideTimestamp : nil
                    store.dispatch(.logHypoTreatment(
                        favorite: favorite,
                        alarmFiredAt: alarmFiredAt,
                        overrideTimestamp: timestamp
                    ))
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "cross.case.fill")
                        Text(isRecheckMode ? "TREAT AGAIN" : "TREAT NOW")
                            .font(DOSTypography.bodyLarge)
                        Text("(\(favorite.mealDescription), \(Int(favorite.carbsGrams ?? 0))g)")
                            .font(DOSTypography.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DOSSpacing.md)
                }
                .buttonStyle(DOSButtonStyle(variant: .primary))
            }

            // Secondary: More options
            Button(action: {
                dismiss()
                onMoreTapped()
            }) {
                HStack {
                    Image(systemName: "list.bullet")
                    Text("More...")
                        .font(DOSTypography.body)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DOSSpacing.sm)
            }
            .buttonStyle(DOSButtonStyle(variant: .ghost))
        }
    }
}
