//
//  WhatsNewPresenter.swift
//  DOSBTS
//
//  Pure present-decision for the in-app "What's New" sheet (DMNC-1147, KTD4).
//  Kept free of AppState so the R4–R7 matrix is unit-testable without a store
//  (mirrors TightControlStreakDetector). The view layer (U6) supplies the
//  current build, last-seen build, and a composed alarm-active flag (KTD7).
//

import Foundation

public enum WhatsNewPresenter {
    /// Decide whether to auto-present the sheet on launch / app-active.
    ///
    /// - `lastSeenBuild == 0` → false: fresh install, the caller records the
    ///   current build silently and presents nothing (R6).
    /// - `alarmActive` → false: defer; the caller must NOT advance last-seen,
    ///   so it presents on a later alarm-free launch (R7).
    /// - `currentBuild <= lastSeenBuild` → false: nothing new (R4).
    /// - otherwise → true.
    public static func shouldPresent(currentBuild: Int, lastSeenBuild: Int, alarmActive: Bool) -> Bool {
        guard lastSeenBuild != 0 else { return false }
        guard !alarmActive else { return false }
        return currentBuild > lastSeenBuild
    }

    /// Builds newer than `lastSeenBuild`, newest-first. `capped` bounds the
    /// auto-sheet's first screen (KTD11); `full` retains every unseen build for
    /// the `SHOW ALL` expansion (R5) and the About history.
    public static func buildsToShow(
        builds: [ChangelogBuild],
        since lastSeenBuild: Int,
        cap: Int = 3
    ) -> (capped: [ChangelogBuild], full: [ChangelogBuild]) {
        let unseen = builds
            .filter { $0.buildNumber > lastSeenBuild }
            .sorted { $0.buildNumber > $1.buildNumber }
        return (Array(unseen.prefix(max(0, cap))), unseen)
    }
}
