//
//  AppConfig.swift
//  DOSBTS
//

import Foundation

// MARK: - AppConfig

enum DirectConfig {
    static let appSchemaURL = URL(staticString: "dosbts://")
    static let bubbleID = "bubble"
    static let calibrationsViewTag = 3
    static let digestViewTag = 5
    static let upstreamDonateURL = URL(staticString: "https://www.paypal.me/creepymonstr")
    static let sponsorURL = URL(staticString: "https://github.com/sponsors/CinimoDY")
    static let expiredNotificationInterval: Double = 1 * 60 * 60 // in seconds
    static let faqURL = URL(staticString: "https://github.com/creepymonster/GlucoseDirect/blob/main/FAQ.md#faq")
    static let githubURL = URL(staticString: "https://github.com/CinimoDY/DOSBTS")
    static let lastChartHours = 24
    static let libre2ID = "libre2"
    static let libreLinkID = "librelink"
    static let listsViewTag = 2
    static let maxReadableGlucose = 501
    static let minGlucoseStatisticsDays = 7
    static let minReadableGlucose = 39
    static let overviewViewTag = 1
    static let projectName = "DOSBTS"
    static let settingsViewTag = 4
    static let smoothThresholdSeconds: Double = 15 * 60
    static let timegroupRounding = 15
    static let virtualID = "virtual"
    static let widgetName = "\(appName) Widget"
    static var bloodGlucoseInput = false
    static var customCalibration = true
    static var glucoseErrors = false
    static var glucoseStatistics = true
    static let showSmoothedGlucose = true
    static var showInsulinInput = true

    static var appName: String = {
        Bundle.main.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
            ?? "DOSBTS"
    }()

    static var appVersion: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }()

    static var appBuild: String = {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }()

    static var appAuthor: String? = {
        Bundle.main.infoDictionary?["AppAuthor"] as? String
    }()

    /// Date the app binary was built. Read from the executable's modification
    /// time — set by the Xcode build system when the binary is produced.
    /// Close enough to "build date" for a TestFlight build ring.
    static var appBuildDate: Date? = {
        guard let executableURL = Bundle.main.executableURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: executableURL.path),
              let modificationDate = attributes[.modificationDate] as? Date else {
            return nil
        }
        return modificationDate
    }()

    static let upstreamGlucoseDirectURL = URL(staticString: "https://github.com/creepymonster/GlucoseDirectApp")

    static var appSupportMail: String? = {
        Bundle.main.infoDictionary?["AppSupportMail"] as? String
    }()

    static var isDebug: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}
