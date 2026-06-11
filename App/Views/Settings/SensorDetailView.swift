//
//  SensorDetailView.swift
//  DOSBTS
//

import SwiftUI

// MARK: - SensorDetailView

/// Full sensor controls + details screen, routable from Settings.
///
/// Migrates the pair/scan/connect/disconnect controls from the legacy
/// `ConnectionView` and the sensor-lifetime / sensor-details / transmitter-details
/// sections from the legacy `SensorView` into a single Settings-routable screen.
///
/// Part of DMNC-793 (Overview no-scroll layout). Task 6 will add the
/// `NavigationLink` to this view from `SettingsView`; Task 9 will delete the
/// original `ConnectionView.swift` and `SensorView.swift`.
struct SensorDetailView: View {
    @EnvironmentObject var store: DirectStore

    @State private var showingDisconnectAlert: Bool = false

    var body: some View {
        List {
            connectionErrorSection
            connectionSection
            sensorLifetimeSection
            sensorDetailsSection
            transmitterSection
        }
        .listStyle(.grouped)
        .navigationTitle("Sensor")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Disconnect sensor?", isPresented: $showingDisconnectAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Disconnect", role: .destructive) {
                withAnimation {
                    store.dispatch(.disconnectConnection)
                }
            }
        } message: {
            Text("You'll need to reconnect the sensor to resume glucose readings.")
        }
    }

    // MARK: - Connection error section

    @ViewBuilder
    private var connectionErrorSection: some View {
        if let connectionError = store.state.connectionError,
           let connectionErrorTimestamp = store.state.connectionErrorTimestamp?.toLocalTime() {
            Section(
                content: {
                    Link(connectionError, destination: DirectConfig.faqURL)
                        .foregroundColor(AmberTheme.cgaRed)

                    HStack {
                        Text("Connection error timestamp")
                        Spacer()
                        Text(connectionErrorTimestamp)
                            .foregroundColor(AmberTheme.amber)
                    }

                    HStack {
                        Text("Help")
                        Spacer()
                        Link("App faq", destination: DirectConfig.faqURL)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                },
                header: {
                    Label("Connection error", systemImage: "exclamationmark.triangle")
                        .foregroundColor(AmberTheme.cgaRed)
                }
            )
        }
    }

    // MARK: - Connection controls (pair / scan / connect / disconnect)

    @ViewBuilder
    private var connectionSection: some View {
        Section(
            content: {
                if store.state.isConnectionPaired {
                    HStack {
                        Text("Connection state")
                        Spacer()
                        Text(store.state.connectionState.localizedDescription)
                            .foregroundColor(AmberTheme.amber)
                    }
                }

                if store.state.hasSelectedConnection {
                    connectionControls
                }
            },
            header: {
                Label("Sensor connection", systemImage: "rectangle.connected.to.line.below")
            }
        )
    }

    @ViewBuilder
    private var connectionControls: some View {
        if store.state.isTransmitter && !store.state.isConnectionPaired {
            Button(
                action: {
                    withAnimation {
                        if store.state.isDisconnectable {
                            store.dispatch(.disconnectConnection)
                        }
                        store.dispatch(.pairConnection)
                    }
                },
                label: {
                    Text("Find transmitter")
                }
            )
            .buttonStyle(DOSButtonStyle())
            .disabled(store.state.connectionIsBusy)
        }

        if store.state.isSensor {
            HStack(spacing: DOSSpacing.sm) {
                Button(
                    action: {
                        withAnimation {
                            if store.state.isDisconnectable {
                                store.dispatch(.disconnectConnection)
                            }
                            store.dispatch(.pairConnection)
                        }
                    },
                    label: {
                        Text("Scan sensor")
                            .frame(maxWidth: .infinity)
                    }
                )
                .buttonStyle(DOSButtonStyle())

                if store.state.isConnectionPaired, store.state.isDisconnectable {
                    Button(
                        action: {
                            showingDisconnectAlert = true
                        },
                        label: {
                            Text("Disconnect")
                                .frame(maxWidth: .infinity)
                        }
                    )
                    .buttonStyle(DOSButtonStyle(variant: .ghost))
                }
            }
        } else if store.state.isConnectionPaired {
            if store.state.isConnectable {
                Button(
                    action: {
                        withAnimation {
                            store.dispatch(.connectConnection)
                        }
                    },
                    label: {
                        if store.state.isTransmitter {
                            Text("Connect transmitter")
                        } else {
                            Text("Connect sensor")
                        }
                    }
                )
                .buttonStyle(DOSButtonStyle())
            } else if store.state.isDisconnectable {
                Button(
                    action: {
                        showingDisconnectAlert = true
                    },
                    label: {
                        Text("Disconnect")
                    }
                )
                .buttonStyle(DOSButtonStyle(variant: .ghost))
            }
        }
    }

    // MARK: - Sensor lifetime

    @ViewBuilder
    private var sensorLifetimeSection: some View {
        if let sensor = store.state.sensor {
            Section(
                content: {
                    HStack {
                        Text("Sensor state")
                        Spacer()
                        Text(sensor.state.localizedDescription)
                            .foregroundColor(AmberTheme.amber)
                    }

                    if sensor.state == .notYetStarted {
                        HStack {
                            Image(systemName: "hand.raised.square")

                            Text("Use LibreLink to start the sensor")
                                .bold()
                        }
                        .foregroundColor(AmberTheme.cgaRed)
                    } else {
                        if let startTimestamp = sensor.startTimestamp {
                            HStack {
                                Text("Sensor starting date")
                                Spacer()
                                Text(startTimestamp.toLocalDateTime())
                                    .foregroundColor(AmberTheme.amber)
                            }
                        }

                        if let endTimestamp = sensor.endTimestamp {
                            HStack {
                                Text("Sensor ending date")
                                Spacer()
                                Text(endTimestamp.toLocalDateTime())
                                    .foregroundColor(AmberTheme.amber)
                            }
                        }

                        if let remainingWarmupTime = sensor.remainingWarmupTime, sensor.state == .starting {
                            VStack {
                                HStack {
                                    Text("Sensor remaining warmup time")
                                    Spacer()
                                    Text(remainingWarmupTime.inTime)
                                        .foregroundColor(AmberTheme.amber)
                                }

                                ProgressView(
                                    "",
                                    value: remainingWarmupTime.toPercent(of: sensor.warmupTime),
                                    total: 100
                                )
                            }
                        } else if sensor.state != .expired && sensor.state != .shutdown && sensor.state != .unknown {
                            HStack {
                                Text("Sensor possible lifetime")
                                Spacer()
                                Text(sensor.lifetime.inTime)
                                    .foregroundColor(AmberTheme.amber)
                            }

                            VStack {
                                HStack {
                                    Text("Sensor age")
                                    Spacer()
                                    Text(sensor.age.inTime)
                                        .foregroundColor(AmberTheme.amber)
                                }

                                ProgressView(
                                    "",
                                    value: sensor.age.toPercent(of: sensor.lifetime),
                                    total: 100
                                )
                            }

                            VStack {
                                HStack {
                                    Text("Sensor remaining lifetime")
                                    Spacer()
                                    Text(sensor.remainingLifetime.inTime)
                                        .foregroundColor(AmberTheme.amber)
                                }

                                ProgressView(
                                    "",
                                    value: sensor.remainingLifetime.toPercent(of: sensor.lifetime),
                                    total: 100
                                )
                            }
                        }
                    }
                },
                header: {
                    Label("Sensor lifetime", systemImage: "timer")
                }
            )
        }
    }

    // MARK: - Sensor details

    @ViewBuilder
    private var sensorDetailsSection: some View {
        if let sensor = store.state.sensor {
            Section(
                content: {
                    HStack {
                        Text("Sensor type")
                        Spacer()
                        Text(sensor.type.localizedDescription)
                            .foregroundColor(AmberTheme.amber)
                    }

                    HStack {
                        Text("Sensor region")
                        Spacer()
                        Text(sensor.region.localizedDescription)
                            .foregroundColor(AmberTheme.amber)
                    }

                    if let serial = sensor.serial {
                        HStack {
                            Text("Sensor serial")
                            Spacer()
                            Text(serial.description)
                                .foregroundColor(AmberTheme.amber)
                        }
                    }

                    if let macAddress = sensor.macAddress {
                        HStack {
                            Text("MAC address")
                            Spacer()
                            Text(macAddress)
                                .foregroundColor(AmberTheme.amber)
                        }
                    }
                },
                header: {
                    Label("Sensor details", systemImage: "text.magnifyingglass")
                }
            )
        }
    }

    // MARK: - Transmitter details

    @ViewBuilder
    private var transmitterSection: some View {
        if let transmitter = store.state.transmitter {
            Section(
                content: {
                    HStack {
                        Text("Transmitter name")
                        Spacer()
                        Text(transmitter.name)
                            .foregroundColor(AmberTheme.amber)
                    }

                    VStack {
                        HStack {
                            Text("Transmitter battery")
                            Spacer()
                            Text(transmitter.battery.asPercent())
                                .foregroundColor(AmberTheme.amber)
                        }

                        ProgressView("", value: Double(transmitter.battery), total: 100)
                    }

                    if let hardware = transmitter.hardware {
                        HStack {
                            Text("Transmitter hardware")
                            Spacer()
                            Text(hardware.description)
                                .foregroundColor(AmberTheme.amber)
                        }
                    }

                    if let firmware = transmitter.firmware {
                        HStack {
                            Text("Transmitter firmware")
                            Spacer()
                            Text(firmware.description)
                                .foregroundColor(AmberTheme.amber)
                        }
                    }
                },
                header: {
                    Label("Transmitter details", systemImage: "antenna.radiowaves.left.and.right.circle")
                }
            )
        }
    }
}

// MARK: - Preview

struct SensorDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            SensorDetailView()
                .environmentObject(
                    DirectStore(
                        initialState: AppState(),
                        reducer: directReducer,
                        middlewares: []
                    )
                )
        }
        .preferredColorScheme(.dark)
    }
}
