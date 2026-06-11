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

                DigestView().tabItem {
                    Label("Daily digest", systemImage: "doc.text.magnifyingglass")
                }.tag(DirectConfig.digestViewTag)
            }
            .overlay {
                if store.state.showScanlines {
                    DOSScanlineOverlay()
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if store.state.appState != newPhase {
                    store.dispatch(.setAppState(appState: newPhase))
                }

                if newPhase == .background, store.state.preventScreenLock {
                    store.dispatch(.setPreventScreenLock(enabled: false))
                }

                if newPhase == .active {
                    WidgetCenter.shared.reloadAllTimelines()
                    if oldPhase != .active {
                        store.dispatch(.incrementAppOpenCount)
                    }
                }
            }
            .onChange(of: store.state.latestSensorGlucose) { _, _ in
                WidgetCenter.shared.reloadAllTimelines()
            }
            .onAppear {
                DirectLog.info("onAppear()")

                // Ensure data loads happen even if scenePhase was already .active
                store.dispatch(.setAppState(appState: .active))

                let appearance = UITabBarAppearance()
                appearance.configureWithOpaqueBackground()
                appearance.backgroundColor = .black

                UITabBar.appearance().scrollEdgeAppearance = appearance
                UITabBar.appearance().standardAppearance = appearance
                UITabBar.appearance().unselectedItemTintColor = UIColor(AmberTheme.amberDark)
                UITabBar.appearance().tintColor = UIColor(AmberTheme.amber)

                // CGA monitor feel: navigation titles render amber monospace
                // on black instead of system white (titles are UIKit-drawn,
                // so the SwiftUI root foregroundStyle can't reach them).
                let navAppearance = UINavigationBarAppearance()
                navAppearance.configureWithOpaqueBackground()
                navAppearance.backgroundColor = .black
                navAppearance.shadowColor = .clear
                navAppearance.titleTextAttributes = [
                    .foregroundColor: UIColor(AmberTheme.amberLight),
                    .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .semibold)
                ]
                navAppearance.largeTitleTextAttributes = [
                    .foregroundColor: UIColor(AmberTheme.amberLight),
                    .font: UIFont.monospacedSystemFont(ofSize: 30, weight: .bold)
                ]
                UINavigationBar.appearance().standardAppearance = navAppearance
                UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
                UINavigationBar.appearance().compactAppearance = navAppearance
                UINavigationBar.appearance().tintColor = UIColor(AmberTheme.amber)
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
