//
//  TreatmentBannerView.swift
//  DOSBTS
//

import SwiftUI
import Combine

struct TreatmentBannerView: View {
    @EnvironmentObject var store: DirectStore

    @State private var remainingSeconds: Int = 0
    @State private var timer: AnyCancellable?
    @State private var autoDismissTask: DispatchWorkItem?
    @State private var currentIOB: Double = 0

    private func refreshBannerIOB() {
        let bolusModel = store.state.bolusInsulinPreset.model
        let basalModel = ExponentialInsulinModel.basal(diaMinutes: store.state.basalDIAMinutes)
        let result = computeIOB(
            deliveries: store.state.iobDeliveries,
            bolusModel: bolusModel,
            basalModel: basalModel
        )
        currentIOB = result.total
    }

    private enum BannerState {
        case countdown
        case rechecking
        case staleData
        case recovered(Int) // glucose value
    }

    private var bannerState: BannerState {
        guard let expiry = store.state.treatmentCycleCountdownExpiry else {
            return .countdown
        }

        if Date() < expiry {
            return .countdown
        }

        // Countdown expired
        if store.state.recheckDispatched {
            if let glucose = store.state.latestSensorGlucose,
               glucose.glucoseValue >= store.state.alarmLow {
                return .recovered(glucose.glucoseValue)
            }
            // Still low case is handled by the modal, not the banner
            return .rechecking
        }

        // Check for stale data (no glucose reading for >5 min after expiry)
        if let latestGlucose = store.state.latestSensorGlucose {
            let staleness = Date().timeIntervalSince(latestGlucose.timestamp)
            if staleness > 5 * 60 {
                return .staleData
            }
        } else {
            return .staleData
        }

        return .rechecking
    }

    /// State-colored toast border for the 4 banner states: green while the
    /// hypo cycle is progressing well (countdown / recovered), amber when it
    /// needs attention (rechecking / stale data). Mirrors the accent color of
    /// each state's own content.
    private var bannerBorderColor: Color {
        switch bannerState {
        case .countdown, .recovered:
            return AmberTheme.cgaGreen
        case .rechecking, .staleData:
            return AmberTheme.amber
        }
    }

    var body: some View {
        HStack(spacing: DOSSpacing.sm) {
            bannerContent

            Spacer()

            Button(action: {
                store.dispatch(.dismissTreatmentCycle)
            }) {
                Image(systemName: "xmark")
                    .font(DOSTypography.caption)
                    .foregroundColor(AmberTheme.amberDark)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DOSSpacing.md)
        .padding(.vertical, DOSSpacing.sm)
        .dosCard(.toast, stroke: bannerBorderColor, padding: nil)
        .onAppear {
            startTimer()
            refreshBannerIOB()
        }
        .onDisappear {
            timer?.cancel()
        }
        .onChange(of: store.state.iobDeliveries.count) { refreshBannerIOB() }
        .onChange(of: store.state.basalDIAMinutes) { refreshBannerIOB() }
        .onChange(of: store.state.bolusInsulinPreset) { refreshBannerIOB() }
    }

    // MARK: - Banner Content

    @ViewBuilder
    private var bannerContent: some View {
        switch bannerState {
        case .countdown:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: DOSSpacing.xs) {
                    Image(systemName: "timer")
                        .foregroundColor(AmberTheme.cgaGreen)
                    Text("HYPO TREATMENT")
                        .font(DOSTypography.caption)
                        .foregroundColor(AmberTheme.cgaGreen)
                    Text("— recheck in \(formattedRemaining)")
                        .font(DOSTypography.caption)
                        .foregroundColor(AmberTheme.amber)
                }
                countdownProgressBar
                if currentIOB > 0.05 {
                    Text("IOB \(String(format: "%.1fU", currentIOB))")
                        .font(DOSTypography.caption)
                        .foregroundColor(AmberTheme.amber)
                }
            }

        case .rechecking:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DOSSpacing.xs) {
                    ProgressView()
                        .tint(AmberTheme.amber)
                    Text("RECHECKING...")
                        .font(DOSTypography.caption)
                        .foregroundColor(AmberTheme.amber)
                }
                if currentIOB > 0.05 {
                    Text("IOB \(String(format: "%.1fU", currentIOB))")
                        .font(DOSTypography.caption)
                        .foregroundColor(AmberTheme.amber)
                }
            }

        case .staleData:
            HStack(spacing: DOSSpacing.xs) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(AmberTheme.amber)
                Text("NO RECENT DATA — CHECK SENSOR")
                    .font(DOSTypography.caption)
                    .foregroundColor(AmberTheme.amber)
            }

        case .recovered(let glucose):
            HStack(spacing: DOSSpacing.xs) {
                Image(systemName: "checkmark.circle")
                    .foregroundColor(AmberTheme.cgaGreen)
                Text("STABILISED AT \(glucose) \(store.state.glucoseUnit.localizedDescription)")
                    .font(DOSTypography.caption)
                    .foregroundColor(AmberTheme.cgaGreen)
            }
            .onAppear {
                // Auto-dismiss after 5 seconds (cancellable if user taps X first)
                let task = DispatchWorkItem { [weak store] in
                    guard let store = store, store.state.treatmentCycleActive else { return }
                    store.dispatch(.endTreatmentCycle)
                }
                autoDismissTask = task
                DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: task)
            }
            .onDisappear {
                autoDismissTask?.cancel()
                autoDismissTask = nil
            }
        }
    }

    // MARK: - Countdown progress

    /// Thin horizontal progress bar filling left-to-right as the recheck
    /// countdown elapses. Gives a continuous visual cue under the M:SS
    /// text so the user doesn't have to read the timer to tell how much
    /// longer until recheck.
    private var countdownProgressBar: some View {
        GeometryReader { geo in
            let total = Double(store.state.hypoTreatmentWaitMinutes * 60)
            let elapsed = max(total - Double(remainingSeconds), 0)
            let progress = total > 0 ? min(elapsed / total, 1) : 0

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(AmberTheme.amberDark.opacity(0.3))
                    .frame(width: geo.size.width, height: 4)

                Rectangle()
                    .fill(AmberTheme.cgaGreen)
                    .frame(width: max(0, geo.size.width * progress), height: 4)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }

    // MARK: - Timer

    private var formattedRemaining: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func startTimer() {
        updateRemaining()
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                updateRemaining()
            }
    }

    private func updateRemaining() {
        guard let expiry = store.state.treatmentCycleCountdownExpiry else {
            remainingSeconds = 0
            return
        }
        let remaining = Int(expiry.timeIntervalSinceNow)
        remainingSeconds = max(0, remaining)
    }
}
