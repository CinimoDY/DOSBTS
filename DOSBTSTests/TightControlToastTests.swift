//
//  TightControlToastTests.swift
//  DOSBTSTests
//
//  U4 (DMNC-772): the toast display model + reveal decision. Pure derivations; the
//  count value itself is reducer-tested in U1 and routing is tested in U3.
//

import Foundation
import Testing
@testable import DOSBTSApp

@Suite("Tight-control toast display model (DMNC-772)")
struct TightControlToastTests {

    @Test("single live streak: 'TIGHT CONTROL' headline + 'N HOURS IN RANGE' sub-line")
    func singleStreakModel() {
        let model = TightControlToastModel(TightControlCelebration(count: 1, hours: 2, withFeedback: true))
        #expect(model.headline == "TIGHT CONTROL")
        #expect(model.subline == "2 HOURS IN RANGE")
    }

    @Test("consolidated streak: 'TIGHT CONTROL ×2' header, no hours sub-line")
    func consolidatedModel() {
        let model = TightControlToastModel(TightControlCelebration(count: 2, hours: nil, withFeedback: true))
        #expect(model.headline == "TIGHT CONTROL ×2")
        #expect(model.subline == nil)
    }

    @Test("single deferred streak (no hours): bare 'TIGHT CONTROL', no sub-line")
    func singleDeferredModel() {
        let model = TightControlToastModel(TightControlCelebration(count: 1, hours: nil, withFeedback: false))
        #expect(model.headline == "TIGHT CONTROL")
        #expect(model.subline == nil)
    }

    @Test("reduce-motion selects the static opacity reveal; motion uses the slide")
    func reduceMotionReveal() {
        #expect(TightControlToastReveal.usesStaticReveal(reduceMotion: true))
        #expect(!TightControlToastReveal.usesStaticReveal(reduceMotion: false))
        #expect(TightControlToastReveal.animation(reduceMotion: true) == nil)
        #expect(TightControlToastReveal.animation(reduceMotion: false) != nil)
    }

    @Test("VoiceOver announcement combines headline and sub-line")
    func voiceOverAnnouncement() {
        #expect(
            TightControlToastController.announcement(for: TightControlCelebration(count: 1, hours: 2, withFeedback: true))
                == "TIGHT CONTROL, 2 HOURS IN RANGE"
        )
        #expect(
            TightControlToastController.announcement(for: TightControlCelebration(count: 3, hours: nil, withFeedback: true))
                == "TIGHT CONTROL ×3"
        )
    }
}
