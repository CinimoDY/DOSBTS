//
//  CalibrationSettingsView.swift
//  DOSBTS
//

import SwiftUI

struct CalibrationSettingsView: View {
    @EnvironmentObject var store: DirectStore

    var body: some View {
        if showCalibrationSection {
            Section(
                content: {
                    CustomCalibrationView()
                    FactoryCalibrationView()
                },
                header: {
                    Label("Calibration", systemImage: "tuningfork")
                }
            )
        }
    }

    private var showCalibrationSection: Bool {
        (store.state.isConnectionPaired && store.state.isConnectable || store.state.isDisconnectable)
            && (DirectConfig.customCalibration || !store.state.customCalibration.isEmpty || store.state.sensor?.factoryCalibration != nil)
    }
}
