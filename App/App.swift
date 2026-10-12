//
//  App.swift
//  DOSBTS
//

import CoreBluetooth
import SwiftUI

#if canImport(CoreNFC)
    import CoreNFC
#endif

// MARK: - DOSBTSApp

@main
struct DOSBTSApp: App {
    // MARK: Lifecycle

    init() {
        #if targetEnvironment(simulator)
            DirectLog.info("Application directory: \(NSHomeDirectory())")
        #endif

        store.dispatch(.startup)
    }

    // MARK: Internal

    @UIApplicationDelegateAdaptor(DOSBTSAppDelegate.self) var appDelegate {
        didSet {
            oldValue.store = nil
            appDelegate.store = store
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(self.store)
                .preferredColorScheme(.dark)
                // True CGA monitor feel: no real white anywhere we control.
                // Unstyled text and symbols fall back to phosphor amber and
                // monospace; interactive chrome tints amber. Explicit CGA
                // accents (green/cyan/red) and system chrome (keyboard,
                // picker internals) are unaffected.
                .tint(AmberTheme.amber)
                .foregroundStyle(AmberTheme.amber)
                .fontDesign(.monospaced)
        }
    }

    // MARK: Private

    private let store: DirectStore = createStore()
}

// MARK: - DOSBTSAppDelegate

class DOSBTSAppDelegate: NSObject, UIApplicationDelegate {
    weak var store: DirectStore?

    func applicationDidFinishLaunching(_ application: UIApplication) {
        DirectLog.info("Application did finish launching")
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        DirectLog.info("Application did finish launching with options")

        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.delegate = self

        // Register notification categories with action buttons
        let tookDextroAction = UNNotificationAction(
            identifier: TreatmentNotificationAction.tookDextro,
            title: "TREAT NOW",
            options: [.foreground]
        )
        let moreOptionsAction = UNNotificationAction(
            identifier: TreatmentNotificationAction.moreOptions,
            title: "More...",
            options: [.foreground]
        )
        let lowGlucoseCategory = UNNotificationCategory(
            identifier: "lowGlucoseAlarm",
            actions: [tookDextroAction, moreOptionsAction],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "",
            options: []
        )

        // Predictive low alarm category — distinct from actual low alarm
        let eatNowAction = UNNotificationAction(
            identifier: TreatmentNotificationAction.eatNow,
            title: "EAT NOW",
            options: [.foreground]
        )
        let predictiveMoreAction = UNNotificationAction(
            identifier: TreatmentNotificationAction.moreOptions,
            title: "More...",
            options: [.foreground]
        )
        let predictiveLowCategory = UNNotificationCategory(
            identifier: "predictiveLowAlarm",
            actions: [eatNowAction, predictiveMoreAction],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "",
            options: []
        )

        notificationCenter.setNotificationCategories([lowGlucoseCategory, predictiveLowCategory])

        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        DirectLog.info("Application will terminate")

        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.delegate = nil

        if let store = store {
            store.dispatch(.shutdown)
        }
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        DirectLog.info("Application did enter background")
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        DirectLog.info("Application did receive memory warning")
    }
}

// MARK: UNUserNotificationCenterDelegate

/// Action identifiers of the low / predictive-low notification buttons —
/// shared by category registration and the response handler.
enum TreatmentNotificationAction {
    static let tookDextro = "tookDextro"
    static let eatNow = "eatNow"
    static let moreOptions = "moreOptions"
}

extension DOSBTSAppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        DirectLog.info("Application will present notification")

        completionHandler([.badge, .banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        DirectLog.info("Application did receive notification response, actionIdentifier: \(response.actionIdentifier)")

        guard let store = store else {
            completionHandler()
            return
        }

        // Recover the original alarm timestamp from notification userInfo (set by GlucoseNotificationService)
        let alarmFiredAt: Date
        if let timestamp = response.notification.request.content.userInfo["alarmFiredAt"] as? TimeInterval {
            alarmFiredAt = Date(timeIntervalSince1970: timestamp)
        } else {
            alarmFiredAt = Date()
        }

        // DMNC-1560: the treatment buttons can be tapped long after the alarm
        // (a notification sitting on the lock screen).
        // - TREAT NOW / EAT NOW are the user saying they ate: honour them
        //   unless there is no usable reading at all (none, or 15+ min old) —
        //   a fresh, recovered reading still logs the treatment and the
        //   recheck reports stabilised.
        // - More... opens the prompt, so it keeps the full currency gate.
        // A refused action only opens Overview.
        let isPredictive = response.notification.request.content.categoryIdentifier == "predictiveLowAlarm"
        let hasUsableReading: Bool = {
            guard let latest = store.state.latestSensorGlucose else { return false }
            if case .veryStale = GlucoseStaleness.of(readingTimestamp: latest.timestamp) { return false }
            return true
        }()
        let isAlarmCurrent = store.state.isTreatmentPromptCurrent(predictive: isPredictive)

        switch response.actionIdentifier {
        case TreatmentNotificationAction.tookDextro, TreatmentNotificationAction.eatNow:
            guard hasUsableReading else {
                DirectLog.info("Treatment action '\(response.actionIdentifier)' without a usable reading — opening Overview only")
                store.dispatch(.selectView(viewTag: DirectConfig.overviewViewTag))
                break
            }

            // Handle both actual low alarm (tookDextro) and predictive alarm (eatNow)
            let hypoTreatments = store.state.favoriteFoodValues
                .filter { $0.isHypoTreatment }
                .sorted { $0.sortOrder < $1.sortOrder }

            if let defaultTreatment = hypoTreatments.first {
                store.dispatch(.logHypoTreatment(favorite: defaultTreatment, alarmFiredAt: alarmFiredAt, overrideTimestamp: nil))
            } else if isAlarmCurrent {
                store.dispatch(.showTreatmentPrompt(alarmFiredAt: alarmFiredAt))
            } else {
                // No default treatment to log, and the prompt would be
                // dropped as no longer current — just open Overview.
                store.dispatch(.selectView(viewTag: DirectConfig.overviewViewTag))
            }

        case TreatmentNotificationAction.moreOptions:
            if isAlarmCurrent {
                store.dispatch(.showTreatmentPrompt(alarmFiredAt: alarmFiredAt))
            } else {
                DirectLog.info("More... on an alarm that is no longer current — opening Overview only")
                store.dispatch(.selectView(viewTag: DirectConfig.overviewViewTag))
            }

        case UNNotificationDefaultActionIdentifier:
            // Body tap — route by userInfo "action"
            let userAction = response.notification.request.content.userInfo["action"] as? String
            switch userAction {
            case "snooze":
                store.dispatch(.selectView(viewTag: DirectConfig.overviewViewTag))
                store.dispatch(.setAlarmSnoozeUntil(untilDate: Date().addingTimeInterval(30 * 60).toRounded(on: 1, .minute)))
            case "openDailyDigest":
                store.dispatch(.selectView(viewTag: DirectConfig.digestViewTag))
            default:
                break
            }

        default:
            break
        }

        completionHandler()
    }
}

private func createStore() -> DirectStore {
    #if targetEnvironment(simulator)
        return createSimulatorAppStore()
    #else
        return createAppStore()
    #endif
}

private func createSimulatorAppStore() -> DirectStore {
    DirectLog.info("Create preview store")

    var middlewares = [
        logMiddleware(),
        bloodGlucoseStoreMiddleware(),
        sensorGlucoseStoreMiddleware(),
        sensorErrorStoreMiddleware(),
        insulinDeliveryStoreMiddleware(),
        iobMiddleware(),
        ratioLabMiddleware(),
        labPatternsMiddleware(),
        labWindowMiddleware(),
        labSweepMiddleware(),
        mealImpactStoreMiddleware(),
        dailyDigestMiddleware(),
        dailyDigestReminderMiddleware(),
        mealEntryStoreMiddleware(),
        favoriteFoodStoreMiddleware(),
        foodCorrectionStoreMiddleware(),
        exerciseEntryStoreMiddleware(),
        treatmentEventStoreMiddleware(),
        journalNoteStoreMiddleware(),
        treatmentCycleMiddleware(),
        tightControlStreakMiddleware(),
        // Cross-middleware: .addMealEntry also handled above by mealEntryStoreMiddleware + favoriteFoodStoreMiddleware
        missedBolusNudgeMiddleware(),
        glucoseStatisticsMiddleware(),
        expiringNotificationMiddleware(),
        glucoseNotificationMiddleware(),
        connectionNotificationMiddleware(),
        appleCalendarExportMiddleware(),
        appleHealthExportMiddleware(),
        appleHealthImportMiddleware(),
        readAloudMiddleware(),
        bellmanAlarmMiddleware(),
        nightscoutMiddleware(),
        appGroupSharingMiddleware(),
        screenLockMiddleware(),
        sensorErrorMiddleware(),
        storeExportMiddleware(),
        clinicReportMiddleware(),
        claudeMiddleware()
    ]

    middlewares.append(widgetCenterMiddleware())

    middlewares.append(sensorConnectorMiddleware([
        SensorConnectionInfo(id: DirectConfig.virtualID, name: "Virtual") { VirtualLibreConnection(subject: $0) }
    ]))

    if DirectConfig.isDebug {
        middlewares.append(debugMiddleware())
    }

    return DirectStore(initialState: AppState(), reducer: directReducer, middlewares: middlewares)
}

private func createAppStore() -> DirectStore {
    DirectLog.info("Create app store")

    var middlewares = [
        logMiddleware(),
        bloodGlucoseStoreMiddleware(),
        sensorGlucoseStoreMiddleware(),
        sensorErrorStoreMiddleware(),
        insulinDeliveryStoreMiddleware(),
        iobMiddleware(),
        ratioLabMiddleware(),
        labPatternsMiddleware(),
        labWindowMiddleware(),
        labSweepMiddleware(),
        mealImpactStoreMiddleware(),
        dailyDigestMiddleware(),
        dailyDigestReminderMiddleware(),
        mealEntryStoreMiddleware(),
        favoriteFoodStoreMiddleware(),
        foodCorrectionStoreMiddleware(),
        exerciseEntryStoreMiddleware(),
        treatmentEventStoreMiddleware(),
        journalNoteStoreMiddleware(),
        treatmentCycleMiddleware(),
        tightControlStreakMiddleware(),
        // Cross-middleware: .addMealEntry also handled above by mealEntryStoreMiddleware + favoriteFoodStoreMiddleware
        missedBolusNudgeMiddleware(),
        glucoseStatisticsMiddleware(),
        expiringNotificationMiddleware(),
        glucoseNotificationMiddleware(),
        connectionNotificationMiddleware(),
        appleCalendarExportMiddleware(),
        appleHealthExportMiddleware(),
        appleHealthImportMiddleware(),
        readAloudMiddleware(),
        bellmanAlarmMiddleware(),
        nightscoutMiddleware(),
        appGroupSharingMiddleware(),
        screenLockMiddleware(),
        sensorErrorMiddleware(),
        storeExportMiddleware(),
        clinicReportMiddleware(),
        claudeMiddleware()
    ]

    middlewares.append(widgetCenterMiddleware())

    var connectionInfos: [SensorConnectionInfo] = []

    #if canImport(CoreNFC)
        if NFCTagReaderSession.readingAvailable {
            connectionInfos.append(SensorConnectionInfo(id: DirectConfig.libre2ID, name: LocalizedString("Without transmitter"), connectionCreator: { LibreConnection(subject: $0) }))
            connectionInfos.append(SensorConnectionInfo(id: DirectConfig.bubbleID, name: LocalizedString("Bubble transmitter"), connectionCreator: { BubbleConnection(subject: $0) }))
        } else {
            connectionInfos.append(SensorConnectionInfo(id: DirectConfig.bubbleID, name: LocalizedString("Bubble transmitter"), connectionCreator: { BubbleConnection(subject: $0) }))
        }
    #else
        connectionInfos.append(SensorConnectionInfo(id: DirectConfig.bubbleID, name: LocalizedString("Bubble transmitter"), connectionCreator: { BubbleConnection(subject: $0) }))
    #endif

    if DirectConfig.isDebug {
        connectionInfos.append(SensorConnectionInfo(id: DirectConfig.libreLinkID, name: LocalizedString("LibreLink transmitter"), connectionCreator: { LibreLinkConnection(subject: $0) }))
    }

    middlewares.append(sensorConnectorMiddleware(connectionInfos))

    if DirectConfig.isDebug {
        middlewares.append(debugMiddleware())
    }

    return DirectStore(initialState: AppState(), reducer: directReducer, middlewares: middlewares)
}
