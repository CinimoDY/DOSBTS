//
//  HasSeenBGRelocationHintReducerTests.swift
//  DOSBTSTests
//

import Foundation
import Testing
@testable import DOSBTSApp

@Suite("hasSeenBGRelocationHint reducer")
struct HasSeenBGRelocationHintReducerTests {

    @Test("setHasSeenBGRelocationHint(seen: true) flips the flag on")
    func reducer_setsHasSeenHint() {
        var state: DirectState = AppState(defaults: makeTestDefaults())
        state.hasSeenBGRelocationHint = false

        directReducer(state: &state, action: .setHasSeenBGRelocationHint(seen: true))

        #expect(state.hasSeenBGRelocationHint == true)
    }

    @Test("setHasSeenBGRelocationHint(seen: false) flips the flag off")
    func reducer_canClearHasSeenHint() {
        var state: DirectState = AppState(defaults: makeTestDefaults())
        state.hasSeenBGRelocationHint = true

        directReducer(state: &state, action: .setHasSeenBGRelocationHint(seen: false))

        #expect(state.hasSeenBGRelocationHint == false)
    }
}
