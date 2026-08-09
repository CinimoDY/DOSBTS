//
//  DictationDisplayModelTests.swift
//  DOSBTSTests
//
//  Pins every branch of `DictationDisplayModel.make` (DMNC-1486).
//
//  The simulator cannot do speech-to-text, so this is where the dictation
//  feature's bugs are caught: the model is the whole decision surface and it
//  needs no audio, no mic, and no device. Same shape as `GlucoseStatusBarTests`.
//

import Foundation
import Testing
@testable import DOSBTSApp

@Suite("DictationDisplayModel state mapping")
struct DictationDisplayModelTests {

    private func make(
        _ availability: SpeechAvailability,
        _ phase: DictationPhase,
        partial: String = "",
        final: String = ""
    ) -> DictationDisplayModel {
        DictationDisplayModel.make(
            availability: availability,
            phase: phase,
            partialText: partial,
            finalText: final
        )
    }

    // MARK: - Availability wins over phase

    @Test("denied renders blocked even mid-listen — a revoked mic must not leave a live UI")
    func deniedOverridesListening() {
        let model = make(.denied, .listening, partial: "200 ml oat milk")
        #expect(model.state == .blocked(.denied))
        #expect(model.showsMic == false)
        #expect(model.showsLevelMeter == false)
        #expect(model.transcriptStyle == nil)
        #expect(model.primaryActionTitle == nil)
    }

    @Test("restricted renders blocked even when a final transcript is in hand")
    func restrictedOverridesReady() {
        let model = make(.restricted, .ready, final: "porridge")
        #expect(model.state == .blocked(.restricted))
        #expect(model.showsMic == false)
    }

    @Test("unsupportedLocale overrides phase and hides the mic entirely")
    func unsupportedLocaleOverridesListening() {
        let model = make(.unsupportedLocale, .listening, partial: "banana")
        #expect(model.state == .unavailable)
        #expect(model.showsMic == false)
    }

    // MARK: - Blocked reasons

    @Test("denied offers a SETTINGS row — the user can reverse it")
    func deniedShowsSettingsRow() {
        let model = make(.denied, .idle)
        #expect(model.showsSettingsRow)
        #expect(model.showsKeyboardHint)
        #expect(model.isErrorMessage == false)
        #expect(model.statusMessage == "MICROPHONE ACCESS OFF")
    }

    @Test("restricted never offers SETTINGS — the toggle it promises is not there")
    func restrictedHidesSettingsRow() {
        let model = make(.restricted, .idle)
        #expect(model.showsSettingsRow == false)
        #expect(model.showsKeyboardHint)
        #expect(model.statusMessage == "MICROPHONE ACCESS RESTRICTED ON THIS DEVICE")
    }

    @Test("both blocked reasons keep the keyboard hint — it is the only thing left that works")
    func bothBlockedReasonsShowKeyboardHint() {
        #expect(make(.denied, .idle).showsKeyboardHint)
        #expect(make(.restricted, .idle).showsKeyboardHint)
    }

    @Test("unsupportedLocale shows the keyboard hint and its own copy, not an error")
    func unsupportedLocaleCopy() {
        let model = make(.unsupportedLocale, .idle)
        #expect(model.state == .unavailable)
        #expect(model.showsKeyboardHint)
        #expect(model.showsSettingsRow == false)
        #expect(model.isErrorMessage == false)
        #expect(model.statusMessage == "DICTATION UNAVAILABLE FOR THIS LANGUAGE")
        #expect(model.primaryActionTitle == nil)
    }

    // MARK: - Phases under an allowed mic

    @Test("available + idle offers SPEAK and nothing else")
    func availableIdle() {
        let model = make(.available, .idle)
        #expect(model.state == .idle)
        #expect(model.primaryActionTitle == "SPEAK")
        #expect(model.showsMic)
        #expect(model.showsKeyboardHint == false)
        #expect(model.showsSettingsRow == false)
        #expect(model.showsLevelMeter == false)
        #expect(model.transcriptStyle == nil)
        #expect(model.statusMessage == nil)
        #expect(model.isErrorMessage == false)
    }

    @Test("needsPermission renders exactly like available — the prompts fire on tap, not at mount")
    func needsPermissionRendersAsIdle() {
        #expect(make(.needsPermission, .idle) == make(.available, .idle))
    }

    @Test("requestingPermission explains the two system prompts and offers no action")
    func requestingPermission() {
        let model = make(.available, .requestingPermission)
        #expect(model.state == .requestingPermission)
        #expect(model.primaryActionTitle == nil)
        #expect(model.showsMic)
        #expect(model.showsLevelMeter == false)
        #expect(model.statusMessage == "ALLOW MICROPHONE AND SPEECH ACCESS")
        #expect(model.isErrorMessage == false)
    }

    @Test("listening carries the partial, meters, and a STOP action")
    func listening() {
        let model = make(.available, .listening, partial: "200 ml oat milk and a ba")
        #expect(model.state == .listening(transcript: "200 ml oat milk and a ba"))
        #expect(model.primaryActionTitle == "STOP")
        #expect(model.showsLevelMeter)
        #expect(model.transcriptStyle == .provisional)
        #expect(model.statusMessage == "LISTENING")
    }

    @Test("listening with nothing heard yet still meters — the user needs to see it is live")
    func listeningEmptyPartial() {
        let model = make(.available, .listening)
        #expect(model.state == .listening(transcript: ""))
        #expect(model.showsLevelMeter)
        #expect(model.transcriptStyle == .provisional)
    }

    @Test("finalizing freezes the partial, drops the meter, and offers no action")
    func finalizingPrefersPartial() {
        let model = make(.available, .finalizing, partial: "oat milk", final: "stale")
        #expect(model.state == .finalizing(transcript: "oat milk"))
        #expect(model.primaryActionTitle == nil)
        #expect(model.showsLevelMeter == false)
        #expect(model.transcriptStyle == .provisional)
        #expect(model.statusMessage == nil)
    }

    @Test("finalizing falls back to finalText when the partial is empty")
    func finalizingFallsBackToFinal() {
        let model = make(.available, .finalizing, partial: "", final: "porridge with berries")
        #expect(model.state == .finalizing(transcript: "porridge with berries"))
    }

    @Test("finalizing with nothing at all still renders, rather than blanking")
    func finalizingEmptyBoth() {
        let model = make(.available, .finalizing)
        #expect(model.state == .finalizing(transcript: ""))
    }

    @Test("ready promotes the final transcript to committed and offers CLEAR")
    func ready() {
        let model = make(.available, .ready, final: "200 ml oat milk and a banana")
        #expect(model.state == .ready(transcript: "200 ml oat milk and a banana"))
        #expect(model.primaryActionTitle == "CLEAR")
        #expect(model.transcriptStyle == .committed)
        #expect(model.showsLevelMeter == false)
        #expect(model.statusMessage == "HEARD")
        #expect(model.isErrorMessage == false)
    }

    @Test("ready ignores a leftover partial — the final result is authoritative")
    func readyIgnoresPartial() {
        let model = make(.available, .ready, partial: "oat mil", final: "oat milk")
        #expect(model.state == .ready(transcript: "oat milk"))
    }

    @Test("ready with an empty final collapses to idle — never arm a paid call with nothing")
    func readyEmptyCollapsesToIdle() {
        let model = make(.available, .ready, partial: "heard something", final: "")
        #expect(model == make(.available, .idle))
        #expect(model.state == .idle)
        #expect(model.primaryActionTitle == "SPEAK")
        #expect(model.transcriptStyle == nil)
    }

    @Test("failed shows the message in error styling with TRY AGAIN")
    func failed() {
        let model = make(.available, .failed("Microphone unavailable"))
        #expect(model.state == .failed(message: "Microphone unavailable"))
        #expect(model.primaryActionTitle == "TRY AGAIN")
        #expect(model.statusMessage == "MICROPHONE UNAVAILABLE")
        #expect(model.isErrorMessage)
        #expect(model.showsMic)
        #expect(model.showsLevelMeter == false)
        #expect(model.transcriptStyle == nil)
        #expect(model.showsSettingsRow == false)
    }

    // MARK: - Transcript styling

    @Test("provisional and committed are the only two transcript styles, and never overlap")
    func transcriptStyleSplit() {
        #expect(make(.available, .listening, partial: "x").transcriptStyle == .provisional)
        #expect(make(.available, .finalizing, partial: "x").transcriptStyle == .provisional)
        #expect(make(.available, .ready, final: "x").transcriptStyle == .committed)
        #expect(make(.available, .idle).transcriptStyle == nil)
        #expect(make(.denied, .idle).transcriptStyle == nil)
    }

    // MARK: - Mic visibility

    @Test("the mic is drawn for every allowed phase and hidden for every disallowed availability")
    func micVisibility() {
        let allowedPhases: [DictationPhase] = [
            .idle, .requestingPermission, .listening, .finalizing, .ready, .failed("boom"),
        ]
        for phase in allowedPhases {
            #expect(
                make(.available, phase, final: "x").showsMic,
                "expected the mic for phase \(phase)"
            )
        }
        for availability in [SpeechAvailability.denied, .restricted, .unsupportedLocale] {
            #expect(
                make(availability, .idle).showsMic == false,
                "expected no mic for availability \(availability)"
            )
        }
    }

    // MARK: - Keyboard hint

    @Test("the keyboard hint appears only when our own mic cannot be offered")
    func keyboardHintOnlyWhenBlocked() {
        #expect(make(.available, .idle).showsKeyboardHint == false)
        #expect(make(.needsPermission, .idle).showsKeyboardHint == false)
        #expect(make(.available, .listening).showsKeyboardHint == false)
        #expect(make(.available, .failed("boom")).showsKeyboardHint == false)
        #expect(make(.denied, .idle).showsKeyboardHint)
        #expect(make(.restricted, .idle).showsKeyboardHint)
        #expect(make(.unsupportedLocale, .idle).showsKeyboardHint)
    }
}
