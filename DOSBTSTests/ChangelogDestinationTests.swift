//
//  ChangelogDestinationTests.swift
//  DOSBTSTests
//
//  U4 (DMNC-1147): the closed-set {tour:} key → navigation resolution (R11),
//  defensive nil on unknown keys (R12), the dispatch-action sequencing, and
//  the selectedSettingsCategory reducer set/clear.
//

import Foundation
import Testing
@testable import DOSBTSApp

@Suite("Changelog destination (DMNC-1147)")
struct ChangelogDestinationTests {

    // MARK: Key resolution (closed set)

    @Test("Tab keys resolve to the matching view tag")
    func tabKeys() {
        #expect(ChangelogDestination(key: "overview") == .tab(DirectConfig.overviewViewTag))
        #expect(ChangelogDestination(key: "lists") == .tab(DirectConfig.listsViewTag))
        #expect(ChangelogDestination(key: "digest") == .tab(DirectConfig.digestViewTag))
    }

    @Test("Settings keys resolve to the settings tab + category")
    func settingsKeys() {
        #expect(ChangelogDestination(key: "settings") == .settings(nil))
        #expect(ChangelogDestination(key: "settings/alarms") == .settings(.alarms))
        #expect(ChangelogDestination(key: "settings/glucose") == .settings(.glucose))
        #expect(ChangelogDestination(key: "settings/insulin") == .settings(.insulin))
        #expect(ChangelogDestination(key: "settings/sensor") == .settings(.sensor))
        #expect(ChangelogDestination(key: "settings/integrations") == .settings(.integrations))
        #expect(ChangelogDestination(key: "settings/about") == .settings(.about))
    }

    @Test("Every closed-set key resolves; the whole set is covered")
    func closedSetComplete() {
        let keys = [
            "overview", "lists", "digest", "settings",
            "settings/alarms", "settings/glucose", "settings/insulin",
            "settings/sensor", "settings/integrations", "settings/about",
        ]
        // 4 tabs (overview/lists/digest/settings-root) + 6 categories = 10.
        #expect(keys.count == 4 + SettingsCategory.allCases.count)
        for key in keys {
            #expect(ChangelogDestination(key: key) != nil, "unresolved key: \(key)")
        }
    }

    @Test("An unknown key resolves to nil (defensive — entry renders plain)")
    func unknownKeyIsNil() {
        #expect(ChangelogDestination(key: "settings/bogus") == nil)
        #expect(ChangelogDestination(key: "calibrations") == nil)
        #expect(ChangelogDestination(key: "") == nil)
    }

    // MARK: Action sequencing

    @Test("A tab destination selects the tab and clears any pushed category")
    func tabActions() {
        let actions = ChangelogDestination.tab(DirectConfig.listsViewTag).actions()
        #expect(actions.count == 2)
        if case let .selectView(viewTag) = actions[0] { #expect(viewTag == DirectConfig.listsViewTag) }
        else { Issue.record("expected selectView first") }
        if case let .setSettingsCategory(category) = actions[1] { #expect(category == nil) }
        else { Issue.record("expected setSettingsCategory(nil) second") }
    }

    @Test("A settings-category destination selects Settings then pushes the category")
    func settingsActions() {
        let actions = ChangelogDestination.settings(.alarms).actions()
        #expect(actions.count == 2)
        if case let .selectView(viewTag) = actions[0] { #expect(viewTag == DirectConfig.settingsViewTag) }
        else { Issue.record("expected selectView(settings) first") }
        if case let .setSettingsCategory(category) = actions[1] { #expect(category == .alarms) }
        else { Issue.record("expected setSettingsCategory(.alarms) second") }
    }

    // MARK: Reducer set / clear

    @Test("setSettingsCategory both sets and clears the transient state")
    func reducerSetAndClear() {
        var state: DirectState = AppState(defaults: makeTestDefaults())
        #expect(state.selectedSettingsCategory == nil)
        directReducer(state: &state, action: .setSettingsCategory(category: .insulin))
        #expect(state.selectedSettingsCategory == .insulin)
        directReducer(state: &state, action: .setSettingsCategory(category: nil))
        #expect(state.selectedSettingsCategory == nil)
    }
}
