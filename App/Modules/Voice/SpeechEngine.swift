//
//  SpeechEngine.swift
//  DOSBTS
//
//  The seam between the dictation UI and whichever speech framework is
//  underneath it (DMNC-1486, decision D5).
//
//  V1 ships `SFSpeechEngine` because `contextualStrings` — biasing recognition
//  toward the foods this user has actually logged — is the single highest
//  leverage quality lever available, and `SpeechTranscriber` does not accept
//  contextual strings at all. When that changes (or `SFSpeechRecognizer` is
//  deprecated), swapping in a `SpeechAnalyzer` implementation is one new file
//  behind this protocol.
//
//  Note this is deliberately NOT an `if #available` shim — the DMNC-776/777/778
//  sweep removed those and none should come back. The deployment target is
//  iOS 26; everything here exists there.
//
//  Nothing in this file — or any implementation of it — may log recognized
//  text. Privacy by design (`docs/development-rules.md`).
//

import Foundation

// MARK: - Transcript

/// One recognition update. `isFinal` is what promotes provisional amberDark
/// text to committed amber in the UI.
struct SpeechTranscript: Equatable {
    let text: String
    let isFinal: Bool
}

// MARK: - Availability

/// Why the mic can or cannot be offered, resolved before any audio starts.
///
/// `blocked` and `unsupported` are distinct on purpose: blocked is a decision
/// the user can reverse in Settings, unsupported is a device/locale fact they
/// cannot. They get different copy and only one of them gets a SETTINGS row.
enum SpeechAvailability: Equatable {
    /// Permissions granted and an on-device recognizer exists for the locale.
    case available
    /// Nothing asked yet — the first mic tap fires the two system prompts.
    case needsPermission
    /// Mic or speech permission denied. Reversible in Settings.
    case denied
    /// MDM / Screen Time. Not reversible by the user, so never offer a retry.
    case restricted
    /// No on-device recognizer for this locale (or the assets are absent).
    /// The mic hides and the keyboard-dictation hint takes its place.
    case unsupportedLocale
}

// MARK: - Errors

enum SpeechEngineError: Error, Equatable {
    /// The audio session or engine refused to start.
    case audioSessionFailed
    /// The recognizer reported a failure mid-utterance.
    case recognitionFailed
    /// Another app or the system took the audio route (call, alarm, Siri).
    case interrupted
    /// Availability was not `.available` when `start` was called.
    case unavailable(SpeechAvailability)
}

// MARK: - Engine

/// A microphone-to-text engine. Implementations own their `AVAudioSession`
/// activation and must release it on `stop`/`cancel` (see `SFSpeechEngine`
/// for the full ownership rules — an alarm has to stay audible through a
/// live dictation, which is a safety requirement, not a nicety).
@MainActor
protocol SpeechEngine: AnyObject {
    /// Current permission + locale support, cheap enough to call on every render.
    var availability: SpeechAvailability { get }

    /// Ask for microphone then speech permission, in that order, and re-resolve
    /// `availability`. Safe to call when already granted (returns immediately).
    func requestAuthorization() async -> SpeechAvailability

    /// Begin recognizing. Emits provisional transcripts as they arrive and one
    /// final transcript before finishing. The stream finishes (rather than
    /// throwing) on a normal `stop`.
    ///
    /// - Parameter contextualStrings: Up to ~100 short phrases biasing
    ///   recognition — the caller passes the user's own food vocabulary.
    func start(contextualStrings: [String]) -> AsyncThrowingStream<SpeechTranscript, Error>

    /// Commit: stop capturing audio but let the recognizer deliver its final
    /// result, then finish the stream.
    func stop()

    /// Abandon: tear everything down immediately, discarding any pending result.
    func cancel()
}
