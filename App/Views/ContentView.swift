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

    /// Single app-level presentation root (R8a): all entry/treatment sheets
    /// present through this coordinator so the chart, quick actions, status
    /// bar, and treatment observers can never create sibling presentation
    /// roots (the wrong-sheet collision class).
    @StateObject private var sheets = SheetCoordinator()

    /// Logging feedback: flashes the just-logged row in whichever list it
    /// lands on (recents, Log tab sections).
    @StateObject private var addedHighlighter = AddedEntryHighlighter()

    var body: some View {
        // TabView is the outermost view so the appIsBusy LoadingOverlay can
        // sit on top via .overlay — wrapping the TabView in another
        // container breaks that z-order.
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
            // Log actions live in a per-tab safeAreaInset bar (KTD-3's named
            // fallback) rather than tabViewBottomAccessory: the accessory's
            // Liquid Glass capsule showed rounded glass edges around the DOS
            // content on lighter tab backgrounds. The inset bar is plain
            // black with sharp edges and never minimizes (R7b).
            .overlay {
                if store.state.showScanlines {
                    DOSScanlineOverlay()
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                LoadingOverlay(isShowing: isShowing)
            }
            .environmentObject(sheets)
            .environmentObject(addedHighlighter)
            .sheet(item: $sheets.activeSheet, onDismiss: sheets.sheetDidDismiss) { sheet in
                RootSheetContent(sheet: sheet)
                    .environmentObject(store)
                    .environmentObject(sheets)
                    .environmentObject(addedHighlighter)
            }
            .onAppear {
                // Cold launch: the prompt flag may already be set before the
                // onChange observers subscribe (e.g. a notification action
                // during launch).
                presentTreatmentSheetIfNeeded()
            }
            .onChange(of: store.state.showTreatmentPrompt) { _, newValue in
                guard newValue else { return }
                presentTreatmentSheetIfNeeded()
            }
            .onChange(of: store.state.recheckDispatched) { _, newValue in
                guard newValue else { return }
                presentTreatmentSheetIfNeeded()
                // If recovered, the banner handles the "STABILISED" state.
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

                // CGA monitor feel for the nav-bar chrome. Title COLORS are
                // not set here: iOS 26's SwiftUI navigation bar ignores
                // UINavigationBar.appearance() title attributes, so visible
                // titles are styled by dosNavigationTitle (principal toolbar
                // item) instead.
                let navAppearance = UINavigationBarAppearance()
                navAppearance.configureWithOpaqueBackground()
                navAppearance.backgroundColor = .black
                navAppearance.shadowColor = .clear
                UINavigationBar.appearance().standardAppearance = navAppearance
                UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
                UINavigationBar.appearance().compactAppearance = navAppearance
                UINavigationBar.appearance().tintColor = UIColor(AmberTheme.amber)
            }
    }

    // MARK: Private

    /// Shared by cold launch and both treatment observers. The stillLow
    /// reducer transition sets BOTH flags at once; the decision function
    /// resolves it to one sheet (recheck wins) and presentSafety's dedup
    /// makes the double observer fire a no-op. Safety presents preempt
    /// whatever sheet is up and land the user on Overview, where the
    /// treatment banner lives (snooze-notification precedent in App.swift).
    private func presentTreatmentSheetIfNeeded() {
        let sheet = SheetCoordinator.treatmentPresent(
            showTreatmentPrompt: store.state.showTreatmentPrompt,
            alarmFiredAt: store.state.alarmFiredAt,
            recheckDispatched: store.state.recheckDispatched,
            treatmentCycleActive: store.state.treatmentCycleActive,
            latestGlucoseValue: store.state.latestSensorGlucose?.glucoseValue,
            alarmLow: store.state.alarmLow
        )
        guard let sheet else { return }

        sheets.presentSafety(sheet)
        store.dispatch(.selectView(viewTag: DirectConfig.overviewViewTag))
        if store.state.showTreatmentPrompt {
            store.dispatch(.setShowTreatmentPrompt(show: false))
        }
    }

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
