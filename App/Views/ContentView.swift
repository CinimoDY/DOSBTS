//
//  ContentView.swift
//  DOSBTS
//

import WidgetKit
import SwiftUI

// MARK: - ContentView

struct ContentView: View {
    // MARK: Internal

    @EnvironmentObject var store: DirectStore
    @Environment(\.scenePhase) var scenePhase

    var body: some View {
        LoadingView(isShowing: isShowing) {
            TabView(selection: selectedView) {
                OverviewView().tabItem {
                    Label("Glucose overview", systemImage: "waveform.path.ecg")
                }.tag(DirectConfig.overviewViewTag)

                ListsView().tabItem {
                    Label("Glucose list view", systemImage: "list.dash")
                }.tag(DirectConfig.listsViewTag)

                SettingsView().tabItem {
                    Label("Settings view", systemImage: "gearshape")
                }.tag(DirectConfig.settingsViewTag)
            }
            .overlay {
                if store.state.showScanlines {
                    DOSScanlineOverlay()
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: scenePhase) { newPhase in
                if store.state.appState != newPhase {
                    store.dispatch(.setAppState(appState: newPhase))
                }

                if newPhase == .background, store.state.preventScreenLock {
                    store.dispatch(.setPreventScreenLock(enabled: false))
                }
                
                if newPhase == .active {
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
            .onChange(of: store.state.latestSensorGlucose, perform: { _ in
                WidgetCenter.shared.reloadAllTimelines()
            })
            .onAppear {
                DirectLog.info("onAppear()")

                let appearance = UITabBarAppearance()
                appearance.configureWithOpaqueBackground()
                appearance.backgroundColor = .black

                UITabBar.appearance().scrollEdgeAppearance = appearance
                UITabBar.appearance().standardAppearance = appearance
                UITabBar.appearance().unselectedItemTintColor = UIColor(AmberTheme.amberDark)
                UITabBar.appearance().tintColor = UIColor(AmberTheme.amber)
            }
        }
    }

    // MARK: Private

    private var isShowing: Binding<Bool> {
        Binding(
            get: { store.state.appIsBusy },
            set: { store.dispatch(.setAppIsBusy(isBusy: $0)) }
        )
    }

    private var selectedView: Binding<Int> {
        Binding(
            get: { store.state.selectedView },
            set: { store.dispatch(.selectView(viewTag: $0)) }
        )
    }
}
