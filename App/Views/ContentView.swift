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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Single app-level presentation root (R8a): all entry/treatment sheets
    /// present through this coordinator so the chart, quick actions, status
    /// bar, and treatment observers can never create sibling presentation
    /// roots (the wrong-sheet collision class).
    @StateObject private var sheets = SheetCoordinator()

    /// Logging feedback: flashes the just-logged row in whichever list it
    /// lands on (recents, Log tab sections).
    @StateObject private var addedHighlighter = AddedEntryHighlighter()

    /// Tight-control streak celebration toast (DMNC-772). Hoisted to ContentView
    /// scope so it sits above all tabs, clear of the per-tab status bar — never a
    /// row inside a tab's VStack (the safeAreaInset-overflow class).
    @StateObject private var tightControlToast = TightControlToastController()

    /// Post-dismiss log confirmation toast (DMNC-1294). Staged during the add
    /// callback (before the sheet closes), then shown in onDismiss so it
    /// appears after the sheet is fully gone. Covers manual meal, insulin, BG.
    @StateObject private var loggedEntryToast = LoggedEntryToastController()

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
            .overlay(alignment: .bottom) {
                if let celebration = tightControlToast.celebration {
                    TightControlToastView(celebration: celebration) {
                        tightControlToast.dismiss()
                    }
                    // Clear the tab bar + the per-tab GlucoseStatusBar (~65pt) so the
                    // toast never collides with the persistent INSULIN/MEAL bar.
                    .padding(.bottom, 116)
                    .transition(TightControlToastReveal.transition(reduceMotion: reduceMotion))
                }
            }
            .animation(TightControlToastReveal.animation(reduceMotion: reduceMotion), value: tightControlToast.celebration)
            .overlay(alignment: .bottom) {
                if let entry = loggedEntryToast.active {
                    LoggedEntryToastView(
                        label: entry.label(glucoseUnit: store.state.glucoseUnit),
                        onUndo: {
                            switch entry {
                            // Log undo — remove the just-logged entry
                            case .meal(let m):
                                store.dispatch(.deleteMealEntry(mealEntry: m))
                            case .insulin(let i):
                                store.dispatch(.deleteInsulinDelivery(insulinDelivery: i))
                            case .insulinBatch(let deliveries):
                                for delivery in deliveries {
                                    store.dispatch(.deleteInsulinDelivery(insulinDelivery: delivery))
                                }
                            case .bloodGlucose(let g):
                                store.dispatch(.deleteBloodGlucose(glucose: g))
                            // Swipe-delete undo — restore via targeted DB-only path to
                            // avoid live-sensor side effects (alarms, HealthKit, Nightscout).
                            case .deletedBloodGlucose(let g):
                                store.dispatch(.restoreBloodGlucose(glucose: g))
                            case .deletedInsulin(let i):
                                store.dispatch(.restoreInsulinDelivery(insulinDelivery: i))
                            case .deletedSensorGlucose(let g):
                                store.dispatch(.restoreSensorGlucose(glucose: g))
                            }
                            loggedEntryToast.dismiss()
                        }
                    )
                    // Clear the tab bar + per-tab GlucoseStatusBar so the toast
                    // never overlaps the persistent INSULIN/MEAL bar.
                    .padding(.bottom, 116)
                }
            }
            .animation(AnimationTokens.easeStandard, value: loggedEntryToast.active)
            .environmentObject(sheets)
            .environmentObject(addedHighlighter)
            .environmentObject(loggedEntryToast)
            .sheet(item: $sheets.activeSheet, onDismiss: {
                sheets.sheetDidDismiss()
                loggedEntryToast.showStagedIfAny()
            }) { sheet in
                RootSheetContent(sheet: sheet)
                    .environmentObject(store)
                    .environmentObject(sheets)
                    .environmentObject(addedHighlighter)
                    .environmentObject(loggedEntryToast)
            }
            .onAppear {
                // Cold launch: the prompt flag may already be set before the
                // onChange observers subscribe (e.g. a notification action
                // during launch). What's New is checked first so its alarm
                // predicate sees the treatment flags before
                // presentTreatmentSheetIfNeeded clears showTreatmentPrompt (R7).
                presentWhatsNewIfNeeded()
                presentTreatmentSheetIfNeeded()
            }
            .onChange(of: store.state.appState) { _, newValue in
                // Foreground returns where the value transitions to .active
                // (the cold-launch-already-active case is covered by onAppear).
                if newValue == .active {
                    presentWhatsNewIfNeeded()
                }
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
            .onChange(of: store.state.tightControlCelebration) { _, newValue in
                guard let newValue else { return }
                tightControlToast.show(newValue)
                // Clear the transient trigger so an identical later celebration re-fires
                // the observer (nil → value), and the store holds no stale celebration.
                store.dispatch(.clearTightControlCelebration)
            }
            .onAppear {
                DirectLog.info("onAppear()")

                // Ensure data loads happen even if scenePhase was already .active
                store.dispatch(.setAppState(appState: .active))

                // Tab bar appearance (DMNC-1029). NOTE: the iOS 26 SwiftUI
                // TabView Liquid Glass bar ignores UITabBar.appearance()
                // entirely — granular item colors, the convenience tint, AND
                // backgroundColor all have no effect (verified empirically,
                // DMNC-1167; see DOSTabBarAppearance + the liquid-glass gotchas
                // doc). Unselected items stay the system secondary color; the
                // selected tint comes from the root .tint(amber) in App.swift.
                // The factory is installed as the correct/forward-compatible
                // config (currently inert), and is the single source of the
                // token→state mapping — the legacy convenience tint setters are
                // intentionally omitted (they only duplicated the same inert
                // mapping; there is no pre-iOS-26 surface in this app to need them).
                let appearance = DOSTabBarAppearance.make()
                UITabBar.appearance().standardAppearance = appearance
                UITabBar.appearance().scrollEdgeAppearance = appearance

                // CGA monitor feel for the nav-bar chrome. Title COLORS are
                // not set here: iOS 26's SwiftUI navigation bar ignores
                // UINavigationBar.appearance() title attributes, so visible
                // titles are styled by dosNavigationTitle (principal toolbar
                // item) instead.
                let navAppearance = UINavigationBarAppearance()
                navAppearance.configureWithOpaqueBackground()
                navAppearance.backgroundColor = UIColor(AmberTheme.dosBlack)
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

    /// Auto-present "What's New" once per update (DMNC-1147). Pure decision in
    /// WhatsNewPresenter; this wiring composes the alarm-active predicate (KTD7),
    /// advances lastSeenBuild at present time (KTD5), and records the build
    /// silently on a fresh install (R6).
    private func presentWhatsNewIfNeeded() {
        // A non-numeric build string is a no-op — never advance, never present.
        guard let currentBuild = Int(DirectConfig.appBuild) else { return }

        let lastSeen = store.state.lastSeenBuild

        // Fresh install (R6): record the current build silently, present nothing.
        if lastSeen == 0 {
            store.dispatch(.setLastSeenBuild(build: currentBuild))
            return
        }

        let alarmActive = store.state.treatmentCycleActive
            || store.state.showTreatmentPrompt
            || store.state.recheckDispatched

        guard WhatsNewPresenter.shouldPresent(
            currentBuild: currentBuild,
            lastSeenBuild: lastSeen,
            alarmActive: alarmActive
        ) else { return }

        let slices = WhatsNewPresenter.buildsToShow(builds: ChangelogParser.bundled(), since: lastSeen)

        // Advance at present time, regardless of whether the bundle happens to
        // carry an entry for this build — so we don't re-check every launch.
        store.dispatch(.setLastSeenBuild(build: currentBuild))

        guard !slices.capped.isEmpty else { return }
        sheets.present(.whatsNew(builds: slices.capped, allBuilds: slices.full))
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
