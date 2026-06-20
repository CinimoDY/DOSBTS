//
//  WhatsNewPresenterTests.swift
//  DOSBTSTests
//
//  U3 (DMNC-1147): the pure What's-New present decision + build filtering, and
//  the lastSeenBuild reducer case. Covers AE1 (fresh install), AE2 (skipped
//  builds, newest-first + cap), AE3 (alarm defers), and the same-build no-op.
//

import Foundation
import Testing
@testable import DOSBTSApp

private func build(_ n: Int) -> ChangelogBuild {
    ChangelogBuild(buildNumber: n, displayName: "\(n)", date: "2026-01-01", sections: [])
}

@Suite("What's New presenter (DMNC-1147)")
struct WhatsNewPresenterTests {

    // MARK: shouldPresent matrix

    @Test("Fresh install (lastSeen 0) never presents, regardless of current build (AE1)")
    func freshInstallNeverPresents() {
        #expect(!WhatsNewPresenter.shouldPresent(currentBuild: 107, lastSeenBuild: 0, alarmActive: false))
        #expect(!WhatsNewPresenter.shouldPresent(currentBuild: 1, lastSeenBuild: 0, alarmActive: false))
    }

    @Test("A newer build with no alarm presents (AE2)")
    func newerBuildPresents() {
        #expect(WhatsNewPresenter.shouldPresent(currentBuild: 107, lastSeenBuild: 104, alarmActive: false))
    }

    @Test("A newer build with an active alarm does not present (AE3)")
    func alarmDefersPresent() {
        #expect(!WhatsNewPresenter.shouldPresent(currentBuild: 107, lastSeenBuild: 104, alarmActive: true))
    }

    @Test("The same build does not present")
    func sameBuildNoPresent() {
        #expect(!WhatsNewPresenter.shouldPresent(currentBuild: 104, lastSeenBuild: 104, alarmActive: false))
    }

    @Test("An older running build does not present")
    func olderBuildNoPresent() {
        #expect(!WhatsNewPresenter.shouldPresent(currentBuild: 103, lastSeenBuild: 104, alarmActive: false))
    }

    // MARK: buildsToShow

    @Test("buildsToShow returns unseen builds newest-first (AE2)")
    func unseenNewestFirst() {
        let all = [build(104), build(105), build(106), build(107)]
        let result = WhatsNewPresenter.buildsToShow(builds: all, since: 104)
        #expect(result.full.map(\.buildNumber) == [107, 106, 105])
        #expect(result.capped.map(\.buildNumber) == [107, 106, 105])
    }

    @Test("The cap bounds the first screen while full retains every unseen build (KTD11)")
    func capBoundsFirstScreen() {
        let all = (100 ... 110).map(build)
        let result = WhatsNewPresenter.buildsToShow(builds: all, since: 100, cap: 3)
        #expect(result.capped.count == 3)
        #expect(result.capped.map(\.buildNumber) == [110, 109, 108])
        #expect(result.full.count == 10) // 101...110
        #expect(result.full.first?.buildNumber == 110)
        #expect(result.full.last?.buildNumber == 101)
    }

    @Test("No unseen builds yields empty slices")
    func noUnseen() {
        let all = [build(104), build(105)]
        let result = WhatsNewPresenter.buildsToShow(builds: all, since: 105)
        #expect(result.capped.isEmpty)
        #expect(result.full.isEmpty)
    }

    // MARK: Reducer

    @Test("setLastSeenBuild records the build")
    func reducerSetsLastSeenBuild() {
        var state: DirectState = AppState(defaults: makeTestDefaults())
        state.lastSeenBuild = 0
        directReducer(state: &state, action: .setLastSeenBuild(build: 106))
        #expect(state.lastSeenBuild == 106)
    }
}
