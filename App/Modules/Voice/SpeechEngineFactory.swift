//
//  SpeechEngineFactory.swift
//  DOSBTS
//
//  The one place that decides which `SpeechEngine` the app runs (DMNC-1486).
//
//  `#if targetEnvironment(simulator)` is a compile-time branch, so a simulator
//  build never compiles `SFSpeechEngine` at all. That is deliberate: the
//  simulator cannot do speech-to-text anyway (broken host-mic passthrough,
//  repeated SFSpeechRecognizer failure reports, one runtime that crashes on
//  granting the speech permission), and `DictationControl` renders its own
//  text-field fallback there — mirroring `BarcodeScannerView`'s simulator
//  branch, which is the house precedent for exactly this problem.
//

import Foundation

/// Builds the engine appropriate to the current build environment.
@MainActor
func makeSpeechEngine() -> SpeechEngine {
    #if targetEnvironment(simulator)
    return StubSpeechEngine()
    #else
    return SFSpeechEngine()
    #endif
}

/// A `SpeechEngine` that never touches the microphone.
///
/// Used on the simulator so the app builds and the whole downstream path
/// (commit → ASK AI → staging plate → SCAN) stays exercisable under
/// `xcodebuild test`. It reports `.available` so the control renders its
/// normal chrome rather than an error state; the simulator branch of
/// `DictationControl` supplies the transcript through the same
/// `onTranscript` callback the real engine feeds.
@MainActor
final class StubSpeechEngine: SpeechEngine {
    private(set) var availability: SpeechAvailability = .available

    func requestAuthorization() async -> SpeechAvailability { availability }

    func start(contextualStrings _: [String]) -> AsyncThrowingStream<SpeechTranscript, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func stop() {}

    func cancel() {}
}
