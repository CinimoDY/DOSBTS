//
//  DictationDisplayModel.swift
//  DOSBTS
//
//  Pure state → render mapping for `DictationControl` (DMNC-1486).
//
//  The simulator cannot do speech-to-text (host-mic passthrough is
//  historically broken and SFSpeechRecognizer has repeated in-simulator
//  failure reports), so every branch that could hold a bug is pushed down
//  here, where it can be tested without audio, a mic, or a device. Same shape
//  as `GlucoseStatusBarModel` and `HypoFilteredEntryModel`: an Equatable
//  struct built by a static `make`, with no view types in the signature.
//

import Foundation

/// What the dictation flow is doing, independent of whether it is *allowed* to.
/// Availability wins over phase — a denied mic renders `blocked` no matter what
/// the controller thinks it is doing.
enum DictationPhase: Equatable {
    case idle
    /// The two system prompts are on screen.
    case requestingPermission
    /// Capturing audio; `partialText` is provisional.
    case listening
    /// Audio stopped, waiting for the recognizer's final result (<1 s).
    case finalizing
    /// Final transcript in hand, armed but not dispatched.
    case ready
    /// Engine, session, or recognizer failure.
    case failed(String)
}

struct DictationDisplayModel: Equatable {
    enum State: Equatable {
        /// Mic affordance only.
        case idle
        /// Waiting on the system permission prompts.
        case requestingPermission
        /// Live provisional transcript + level meter + STOP.
        case listening(transcript: String)
        /// Frozen transcript + loading dots.
        case finalizing(transcript: String)
        /// Committed transcript, editable, CLEAR + the caller's confirm action.
        case ready(transcript: String)
        /// Permission problem. Reversible or not, per `BlockReason`.
        case blocked(BlockReason)
        /// No on-device recognizer for this locale — the mic is hidden entirely.
        case unavailable
        /// Recoverable failure; TRY AGAIN returns to idle.
        case failed(message: String)
    }

    enum BlockReason: Equatable {
        /// User said no. Fixable in Settings.
        case denied
        /// MDM / Screen Time. Never offer a retry — it cannot succeed.
        case restricted
    }

    /// Which amber the transcript renders in. The dim/bright split is the whole
    /// point of showing partials: the user sees a misheard food name while they
    /// can still restate it.
    enum TranscriptStyle: Equatable {
        /// `AmberTheme.amberDark` + blinking block cursor.
        case provisional
        /// `AmberTheme.amber`, editable.
        case committed
    }

    let state: State
    /// Title of the one primary button, or nil when the state has no action.
    let primaryActionTitle: String?
    /// Whether to draw the mic affordance at all.
    let showsMic: Bool
    /// The Option-0 fallback line — the keyboard's own mic key still works, and
    /// it is the only thing left to offer once we cannot open ours.
    let showsKeyboardHint: Bool
    /// Only for `.denied`; a restricted device cannot be fixed in Settings.
    let showsSettingsRow: Bool
    /// Whether the live level meter animates.
    let showsLevelMeter: Bool
    let transcriptStyle: TranscriptStyle?
    /// One-line explanatory copy, already uppercased for DOS rendering.
    let statusMessage: String?
    /// True when the message should render in `AmberTheme.cgaRed`.
    let isErrorMessage: Bool

    // MARK: - Construction

    static func make(
        availability: SpeechAvailability,
        phase: DictationPhase,
        partialText: String,
        finalText: String
    ) -> DictationDisplayModel {
        // Availability is checked first and unconditionally: a permission that
        // was revoked in Settings while the sheet sat open must not leave a
        // stale `listening` UI on screen.
        switch availability {
        case .denied:
            return blocked(.denied)
        case .restricted:
            return blocked(.restricted)
        case .unsupportedLocale:
            return DictationDisplayModel(
                state: .unavailable,
                primaryActionTitle: nil,
                showsMic: false,
                showsKeyboardHint: true,
                showsSettingsRow: false,
                showsLevelMeter: false,
                transcriptStyle: nil,
                statusMessage: "DICTATION UNAVAILABLE FOR THIS LANGUAGE",
                isErrorMessage: false
            )
        case .available, .needsPermission:
            break
        }

        switch phase {
        case .idle:
            return DictationDisplayModel(
                state: .idle,
                primaryActionTitle: "SPEAK",
                showsMic: true,
                showsKeyboardHint: false,
                showsSettingsRow: false,
                showsLevelMeter: false,
                transcriptStyle: nil,
                statusMessage: nil,
                isErrorMessage: false
            )

        case .requestingPermission:
            return DictationDisplayModel(
                state: .requestingPermission,
                primaryActionTitle: nil,
                showsMic: true,
                showsKeyboardHint: false,
                showsSettingsRow: false,
                showsLevelMeter: false,
                transcriptStyle: nil,
                statusMessage: "ALLOW MICROPHONE AND SPEECH ACCESS",
                isErrorMessage: false
            )

        case .listening:
            return DictationDisplayModel(
                state: .listening(transcript: partialText),
                primaryActionTitle: "STOP",
                showsMic: true,
                showsKeyboardHint: false,
                showsSettingsRow: false,
                showsLevelMeter: true,
                transcriptStyle: .provisional,
                statusMessage: "LISTENING",
                isErrorMessage: false
            )

        case .finalizing:
            // Keep showing whatever was heard. An interruption (call, alarm)
            // lands here, and throwing away the words the user already said
            // would be the worst possible response to being interrupted.
            return DictationDisplayModel(
                state: .finalizing(transcript: partialText.isEmpty ? finalText : partialText),
                primaryActionTitle: nil,
                showsMic: true,
                showsKeyboardHint: false,
                showsSettingsRow: false,
                showsLevelMeter: false,
                transcriptStyle: .provisional,
                statusMessage: nil,
                isErrorMessage: false
            )

        case .ready:
            // A final result that came back empty is not a transcript worth
            // arming a paid AI call with — fall back to idle so the user just
            // taps SPEAK again.
            guard !finalText.isEmpty else {
                return make(
                    availability: availability,
                    phase: .idle,
                    partialText: "",
                    finalText: ""
                )
            }
            return DictationDisplayModel(
                state: .ready(transcript: finalText),
                primaryActionTitle: "CLEAR",
                showsMic: true,
                showsKeyboardHint: false,
                showsSettingsRow: false,
                showsLevelMeter: false,
                transcriptStyle: .committed,
                statusMessage: "HEARD",
                isErrorMessage: false
            )

        case let .failed(message):
            return DictationDisplayModel(
                state: .failed(message: message),
                primaryActionTitle: "TRY AGAIN",
                showsMic: true,
                showsKeyboardHint: false,
                showsSettingsRow: false,
                showsLevelMeter: false,
                transcriptStyle: nil,
                statusMessage: message.uppercased(),
                isErrorMessage: true
            )
        }
    }

    /// Both blocked reasons show the keyboard hint — it is the only alternative
    /// that still works — but only `denied` gets a SETTINGS row, because a
    /// restricted device will not present the toggle the row promises.
    private static func blocked(_ reason: BlockReason) -> DictationDisplayModel {
        DictationDisplayModel(
            state: .blocked(reason),
            primaryActionTitle: nil,
            showsMic: false,
            showsKeyboardHint: true,
            showsSettingsRow: reason == .denied,
            showsLevelMeter: false,
            transcriptStyle: nil,
            statusMessage: reason == .denied
                ? "MICROPHONE ACCESS OFF"
                : "MICROPHONE ACCESS RESTRICTED ON THIS DEVICE",
            isErrorMessage: false
        )
    }
}
