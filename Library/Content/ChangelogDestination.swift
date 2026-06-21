//
//  ChangelogDestination.swift
//  DOSBTS
//
//  Deep-link feature tour (DMNC-1147, KTD3). A changelog entry's optional
//  `{tour:<key>}` marker resolves to a navigation target at tab / Settings-
//  category granularity (R11) — never an individual control. The key set is
//  closed; an unknown key resolves to nil and the entry renders plain (R12).
//

import Foundation

// MARK: - SettingsCategory

/// The six Settings hub categories (SettingsView). Used both as a deep-link
/// target and as the transient `selectedSettingsCategory` push state. Settings-
/// category navigation is net-new (KTD6) — there is no programmatic push today.
public enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
    case alarms
    case glucose
    case insulin
    case sensor
    case integrations
    case about

    public var id: String { rawValue }
}

// MARK: - ChangelogDestination

public enum ChangelogDestination: Equatable {
    /// Switch to a top-level tab (by `DirectConfig` view tag).
    case tab(Int)
    /// Switch to the Settings tab, optionally pushing a category.
    case settings(SettingsCategory?)

    /// Resolve a closed-set `{tour:<key>}` key. Unknown keys → nil (defensive,
    /// so a typo in a future entry degrades to a plain, non-interactive line).
    public init?(key: String) {
        switch key {
        case "overview": self = .tab(DirectConfig.overviewViewTag)
        case "lists": self = .tab(DirectConfig.listsViewTag)
        case "digest": self = .tab(DirectConfig.digestViewTag)
        case "settings": self = .settings(nil)
        case "settings/alarms": self = .settings(.alarms)
        case "settings/glucose": self = .settings(.glucose)
        case "settings/insulin": self = .settings(.insulin)
        case "settings/sensor": self = .settings(.sensor)
        case "settings/integrations": self = .settings(.integrations)
        case "settings/about": self = .settings(.about)
        default: return nil
        }
    }

    /// The Redux actions that perform the navigation, in dispatch order. Pure
    /// so the routing is unit-testable; U6 dispatches these after dismissing the
    /// auto-sheet (dismiss-then-navigate, never a nested sheet — KTD6).
    /// Internal (not public): `DirectAction` is an internal type.
    func actions() -> [DirectAction] {
        switch self {
        case let .tab(tag):
            // Leaving any pushed Settings category behind keeps a later Settings
            // visit at its root.
            return [.selectView(viewTag: tag), .setSettingsCategory(category: nil)]
        case let .settings(category):
            return [
                .selectView(viewTag: DirectConfig.settingsViewTag),
                .setSettingsCategory(category: category),
            ]
        }
    }
}
