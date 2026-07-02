//
//  GlucoseView.swift
//  DOSBTS
//

import SwiftUI

// MARK: - GlucoseView

struct GlucoseView: View {
    // MARK: Internal

    @EnvironmentObject var store: DirectStore
    @State private var lowPulse = false
    @State private var iobResult = IOBResult(total: 0, mealSnackIOB: 0, correctionBasalIOB: 0)
    @State private var iobTimer: Timer?
    @State private var showingConnectDialog = false

    var body: some View {
        VStack(spacing: 0) {
            if let latestGlucose = store.state.latestSensorGlucose {
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    if latestGlucose.type != .high {
                        Text(verbatim: latestGlucose.glucoseValue.asGlucose(glucoseUnit: store.state.glucoseUnit))
                            .font(DOSTypography.glucoseHero)
                            .foregroundStyle(getGlucoseColor(glucose: latestGlucose))
                            .dosGlowLarge(color: getGlucoseColor(glucose: latestGlucose))
                            .opacity(isDangerouslyLow ? (lowPulse ? 0.4 : 1.0) : 1.0)
                            .animation(isDangerouslyLow ? AnimationTokens.pulse : .default,
                                value: lowPulse
                            )
                            .onAppear { lowPulse = true }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: latestGlucose.trend.description)
                                .foregroundStyle(getGlucoseColor(glucose: latestGlucose))
                                .font(DOSTypography.mono(size: 36, weight: .bold))

                            if let minuteChange = latestGlucose.minuteChange?.asMinuteChange(glucoseUnit: store.state.glucoseUnit) {
                                Text(verbatim: minuteChange)
                                    .font(DOSTypography.caption)
                            } else {
                                Text(verbatim: "?")
                                    .font(DOSTypography.caption)
                            }
                        }
                    } else {
                        Text("HIGH")
                            .font(DOSTypography.glucoseHero)
                            .foregroundStyle(AmberTheme.cgaRed)
                            .dosGlowLarge(color: AmberTheme.cgaRed)
                    }
                }

                if let staleLabel = staleness.minutesAgoLabel {
                    HStack(spacing: DOSSpacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(verbatim: staleLabel)
                    }
                    .font(DOSTypography.caption)
                    .foregroundStyle(AmberTheme.stalenessColor(staleness))
                    .padding(.top, 2)
                }

                if let warning = warning {
                    Text(verbatim: warning)
                        .font(DOSTypography.bodySmall)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(AmberTheme.cgaRed)
                        .foregroundStyle(AmberTheme.dosBlack)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            DirectNotifications.shared.hapticFeedback()
                            showingConnectDialog = true
                        }
                        .accessibilityLabel("\(warning), tap to reconnect")
                        .accessibilityHint("Opens reconnect options")
                } else {
                    Text(verbatim: store.state.glucoseUnit.localizedDescription)
                        .font(DOSTypography.caption)
                        .opacity(0.5)
                }

                if iobResult.total > 0 {
                    iobLabel
                }

            } else {
                Text("No Data")
                    .font(DOSTypography.mono(size: 42, weight: .bold))
                    .foregroundStyle(AmberTheme.cgaRed)

                Text(verbatim: "---")
                    .font(DOSTypography.caption)
                    .opacity(0.5)

                if iobResult.total > 0 {
                    iobLabel
                }
            }

            // Active-state row: only renders when screen-lock prevention is on
            // OR an alarm snooze is active. Each control carries a text label so
            // its purpose is obvious; entry paths live elsewhere (Settings →
            // Additional settings for screen lock; alarm notification "Snooze"
            // action for snoozes).
            if store.state.preventScreenLock || store.state.alarmSnoozeUntil != nil {
                // Left-aligned (user request): the snooze/screen-lock status
                // reads as a meta line under the hero, not a centered badge.
                HStack {
                    if store.state.preventScreenLock {
                        Button(action: {
                            DirectNotifications.shared.hapticFeedback()
                            store.dispatch(.setPreventScreenLock(enabled: false))
                        }, label: {
                            Image(systemName: "lock.slash")
                            Text("Screen lock off")
                        })
                    }

                    if let alarmSnoozeUntil = store.state.alarmSnoozeUntil {
                        Button(action: {
                            DirectNotifications.shared.hapticFeedback()
                            store.dispatch(.setAlarmSnoozeUntil(untilDate: nil))
                        }, label: {
                            Image(systemName: "delete.forward")
                        }).padding(.trailing, 5)

                        Button(action: {
                            // Tap the snooze label to extend by 30 minutes.
                            let date = alarmSnoozeUntil.toRounded(on: 1, .minute)
                            let nextDate = Calendar.current.date(byAdding: .minute, value: 30, to: date)

                            DirectNotifications.shared.hapticFeedback()
                            store.dispatch(.setAlarmSnoozeUntil(untilDate: nextDate))
                        }, label: {
                            Image(systemName: "speaker.slash")
                            Text("Snoozed until \(alarmSnoozeUntil.toLocalTime())")
                        })
                    }

                    Spacer()
                }
                .font(DOSTypography.caption)
                .padding(.top, DOSSpacing.xs)
                .padding(.horizontal, DOSSpacing.md)
                .disabled(store.state.latestSensorGlucose == nil)
                .buttonStyle(.plain)
            }
        }
        .onChange(of: store.state.iobDeliveries.count) { refreshIOB() }
        .onChange(of: store.state.latestSensorGlucose?.timestamp) { refreshIOB() }
        .onChange(of: store.state.bolusInsulinPreset) { refreshIOB() }
        .onChange(of: store.state.basalDIAMinutes) { refreshIOB() }
        .confirmationDialog("Reconnect sensor?", isPresented: $showingConnectDialog, titleVisibility: .visible) {
            Button("Connect (BLE)") {
                DirectNotifications.shared.hapticFeedback()
                store.dispatch(.connectConnection)
            }
            Button("Scan Sensor (NFC)") {
                DirectNotifications.shared.hapticFeedback()
                store.dispatch(.pairConnection)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Connect: fast reconnect to the existing session. Scan: full NFC re-scan for a new or expired sensor.")
        }
        .onAppear {
            refreshIOB()
            iobTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
                refreshIOB()
            }
        }
        .onDisappear {
            iobTimer?.invalidate()
            iobTimer = nil
        }
    }

    // MARK: Private

    private var warning: String? {
        if let sensor = store.state.sensor, sensor.state != .ready {
            return sensor.state.localizedDescription
        }

        if store.state.connectionState != .connected {
            return store.state.connectionState.localizedDescription
        }

        return nil
    }

    /// Shared with GlucoseStatusBar (KTD-4) — hero and bar never disagree
    /// on stale salience.
    private var staleness: GlucoseStaleness {
        guard let glucose = store.state.latestSensorGlucose else { return .fresh }
        return GlucoseStaleness.of(readingTimestamp: glucose.timestamp)
    }

    @ViewBuilder
    private var iobLabel: some View {
        HStack(alignment: .firstTextBaseline, spacing: DOSSpacing.xxs) {
            Text("IOB")
                .font(DOSTypography.label)
                .tracking(0.6)
                .foregroundStyle(AmberTheme.amber)

            if store.state.showSplitIOB && (iobResult.mealSnackIOB > 0 || iobResult.correctionBasalIOB > 0) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(formatIOB(iobResult.mealSnackIOB))
                        .font(DOSTypography.mono(size: 14, weight: .semibold))
                        .foregroundStyle(AmberTheme.iobBolus)
                    Text("BOLUS")
                        .font(DOSTypography.mono(size: 9, weight: .medium))
                        .tracking(0.4)
                        .foregroundStyle(AmberTheme.iobBolus.opacity(0.7))
                }
                Text("·")
                    .font(DOSTypography.mono(size: 11))
                    .foregroundStyle(AmberTheme.borderStrong)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(formatIOB(iobResult.correctionBasalIOB))
                        .font(DOSTypography.mono(size: 14, weight: .semibold))
                        .foregroundStyle(AmberTheme.iobBasal)
                    Text("BASAL")
                        .font(DOSTypography.mono(size: 9, weight: .medium))
                        .tracking(0.4)
                        .foregroundStyle(AmberTheme.iobBasal.opacity(0.7))
                }
            } else {
                Text(formatIOB(iobResult.total))
                    .font(DOSTypography.mono(size: 14, weight: .semibold))
                    .foregroundStyle(AmberTheme.iobBolus)
            }
        }
    }

    private func formatIOB(_ value: Double) -> String {
        String(format: "%.1fU", value)
    }

    private func refreshIOB() {
        let bolusModel = store.state.bolusInsulinPreset.model
        let basalModel = ExponentialInsulinModel.basal(diaMinutes: store.state.basalDIAMinutes)
        iobResult = computeIOB(
            deliveries: store.state.iobDeliveries,
            bolusModel: bolusModel,
            basalModel: basalModel
        )
    }

    private var isDangerouslyLow: Bool {
        guard let glucose = store.state.latestSensorGlucose else { return false }
        return glucose.glucoseValue < store.state.alarmLow
    }

    private func getGlucoseColor(glucose: any Glucose) -> Color {
        AmberTheme.glucoseColor(forValue: glucose.glucoseValue, low: store.state.alarmLow, high: store.state.alarmHigh)
    }
}
