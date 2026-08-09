//
//  SensorLineView.swift
//  DOSBTS
//

import SwiftUI

/// Publishes the trailing action chip's own rendered width so the centered
/// label can reserve exactly that much room (see `SensorLineView.body`).
/// `max` (not last-wins) so a transient 0 from a disappearing chip cannot
/// collapse the reservation mid-transition.
private struct ChipWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct SensorLineView: View {
    @EnvironmentObject var store: DirectStore
    @State private var disconnectChipRevealed: Bool = false
    @State private var showingDisconnectAlert: Bool = false
    @State private var showingConnectDialog: Bool = false
    @State private var measuredChipWidth: CGFloat = 0

    var body: some View {
        // Status (dot + "CONNECTED · 3d 2h LEFT") is centered; the action
        // chips (CONNECT / disconnect) keep the trailing edge. The label uses
        // the compact remaining-time format (days+hours, no minutes) so it fits.
        // The chip-width reservation (which keeps the label optically centered
        // next to a chip) is applied ONLY when a chip is actually shown —
        // reserving it in the common chip-less connected state wasted ~172pt and
        // forced the label to truncate, hiding the days/hours. minimumScaleFactor
        // is a final safety net so magnitude is never dropped. The reservation
        // width itself is measured, not hard-coded: the trailing chip publishes
        // its own rendered width via ChipWidthKey, so the label reserves exactly
        // what the chip needs at any Dynamic Type size instead of a constant
        // that silently drifts out of sync with the chip's actual content.
        ZStack {
            dotAndLabel
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, reservesChipWidth ? max(measuredChipWidth, DOSSpacing.md) : DOSSpacing.md)

            HStack {
                Spacer()
                trailingContent
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: ChipWidthKey.self, value: geo.size.width)
                        }
                    )
            }
        }
        .onPreferenceChange(ChipWidthKey.self) { measuredChipWidth = $0 }
        .padding(.horizontal, DOSSpacing.md)
        .padding(.vertical, DOSSpacing.xs)
        .contentShape(Rectangle())
        .onTapGesture(perform: handleRowTap)
        .onChange(of: store.state.connectionState) { _, newState in
            if newState == .connected {
                DirectNotifications.shared.hapticNotification(.success)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelString)
        .accessibilityHint(accessibilityHintString)
        .alert("Disconnect sensor?", isPresented: $showingDisconnectAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Disconnect", role: .destructive) {
                store.dispatch(.disconnectConnection)
                disconnectChipRevealed = false
            }
        } message: {
            Text("You'll need to reconnect the sensor to resume glucose readings.")
        }
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
    }

    // MARK: - Row parts

    private var dotAndLabel: some View {
        HStack(spacing: DOSSpacing.xxs) {
            if store.state.activeAlarmProfile == .night {
                Image(systemName: "moon.fill")
                    .font(DOSTypography.caption)
                    .foregroundStyle(AmberTheme.amberDark)
                    .accessibilityHidden(true)
            }
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(labelText)
                .font(DOSTypography.caption)
                .foregroundStyle(labelColor)
                .bold(isConnected)
            if currentState == .transient {
                // Warmup can sit here ~60 min — use the low-power cadence so the
                // pulse doesn't drive a continuous full-rate render loop.
                FiguresLoadingView(dotSize: 5, spacing: 3, color: AmberTheme.amberLight, cadence: .lowPower)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var trailingContent: some View {
        switch currentState {
        case .connected:
            if disconnectChipRevealed {
                Button {
                    showingDisconnectAlert = true
                } label: {
                    Text("DISCONNECT")
                        .font(DOSTypography.caption)
                        .foregroundStyle(AmberTheme.amber)
                        .fixedSize()
                        .padding(.horizontal, DOSSpacing.sm)
                        .padding(.vertical, 3)
                        .overlay(
                            Rectangle().stroke(AmberTheme.amber, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        case .disconnected:
            Button {
                DirectNotifications.shared.hapticFeedback()
                showingConnectDialog = true
            } label: {
                Text("CONNECT")
                    .font(DOSTypography.caption)
                    .foregroundStyle(AmberTheme.amber)
                    .fixedSize()
                    .padding(.horizontal, DOSSpacing.sm)
                    .padding(.vertical, 3)
                    .overlay(
                        Rectangle().stroke(AmberTheme.amber, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        case .noSensor:
            Text("SET UP")
                .font(DOSTypography.caption)
                .foregroundStyle(AmberTheme.amberDark)
                .fixedSize()
                .padding(.horizontal, DOSSpacing.sm)
                .padding(.vertical, 3)
                .overlay(
                    Rectangle().stroke(AmberTheme.amberDark, lineWidth: 1)
                )
        case .error, .bluetoothOff, .transient, .unknown:
            EmptyView()
        }
    }

    // MARK: - State resolution

    private enum ResolvedState {
        case connected
        case disconnected
        case noSensor
        case error
        case bluetoothOff
        case transient  // connecting / scanning / pairing / warmup
        case unknown
    }

    private var currentState: ResolvedState {
        if store.state.connectionError != nil {
            return .error
        }
        if store.state.connectionState == .powerOff {
            return .bluetoothOff
        }
        if !store.state.hasSelectedConnection {
            return .noSensor
        }
        if store.state.connectionState == .connected {
            return .connected
        }
        if [.connecting, .scanning, .pairing].contains(store.state.connectionState) {
            return .transient
        }
        if store.state.connectionState == .disconnected {
            return .disconnected
        }
        return .unknown
    }

    private var isConnected: Bool { currentState == .connected }

    private var dotColor: Color {
        switch currentState {
        case .connected: return AmberTheme.cgaGreen
        case .transient: return AmberTheme.amberLight
        case .disconnected, .noSensor: return AmberTheme.amberDark
        case .error, .bluetoothOff: return AmberTheme.cgaRed
        case .unknown: return AmberTheme.amberDark
        }
    }

    private var labelColor: Color {
        switch currentState {
        case .connected: return AmberTheme.cgaGreen
        case .transient: return AmberTheme.amberLight
        case .disconnected, .noSensor: return AmberTheme.amberDark
        case .error, .bluetoothOff: return AmberTheme.cgaRed
        case .unknown: return AmberTheme.amberDark
        }
    }

    /// Whether `trailingContent` renders a chip for the current state. The
    /// centered label only needs to reserve chip width when one is present.
    private var reservesChipWidth: Bool {
        switch currentState {
        case .connected: return disconnectChipRevealed
        case .disconnected, .noSensor: return true
        case .error, .bluetoothOff, .transient, .unknown: return false
        }
    }

    private var labelText: String {
        switch currentState {
        case .connected:
            if let sensor = store.state.sensor {
                return "CONNECTED · \(sensor.remainingLifetime.inTimeCompact) LEFT"
            }
            return "CONNECTED"
        case .transient:
            if let sensor = store.state.sensor, sensor.state == .starting, let warmup = sensor.remainingWarmupTime {
                return "WARMUP · \(warmup.inTimeCompact) LEFT"
            }
            switch store.state.connectionState {
            case .connecting: return "CONNECTING…"
            case .scanning: return "SCANNING…"
            case .pairing: return "PAIRING…"
            default: return "…"
            }
        case .disconnected: return "DISCONNECTED"
        case .noSensor: return "NO SENSOR"
        case .error: return "CONNECTION ERROR"
        case .bluetoothOff: return "BLUETOOTH OFF"
        case .unknown: return "—"
        }
    }

    // MARK: - Interaction

    private func handleRowTap() {
        switch currentState {
        case .connected:
            disconnectChipRevealed.toggle()
        case .bluetoothOff:
            if let url = URL(string: "App-Prefs:Bluetooth") {
                UIApplication.shared.open(url)
            }
        default:
            break
        }
    }

    // MARK: - Accessibility

    private var accessibilityLabelString: String {
        let nightPrefix = store.state.activeAlarmProfile == .night ? "Night profile active. " : ""
        let core: String
        switch currentState {
        case .connected:
            if let sensor = store.state.sensor {
                core = "Sensor connected, \(sensor.remainingLifetime.inTime) remaining"
            } else {
                core = "Sensor connected"
            }
        case .transient: core = labelText.lowercased().capitalized
        case .disconnected: core = "Sensor disconnected"
        case .noSensor: core = "No sensor set up"
        case .error: core = "Connection error"
        case .bluetoothOff: core = "Bluetooth is off"
        case .unknown: core = "Sensor state unknown"
        }
        return nightPrefix + core
    }

    private var accessibilityHintString: String {
        switch currentState {
        case .connected:
            return disconnectChipRevealed ? "Double-tap the disconnect chip to disconnect" : "Double-tap to reveal disconnect"
        case .disconnected: return "Double-tap the connect chip for reconnect options"
        case .bluetoothOff: return "Double-tap to open iOS Bluetooth settings"
        default: return ""
        }
    }
}

struct SensorLineView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: DOSSpacing.md) {
            SensorLineView()
                .environmentObject(DirectStore(initialState: AppState(), reducer: directReducer, middlewares: []))
        }
        .background(AmberTheme.dosBlack)
        .preferredColorScheme(.dark)
    }
}
