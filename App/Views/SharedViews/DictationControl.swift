//
//  DictationControl.swift
//  DOSBTS
//
//  The one reusable dictation affordance (DMNC-1486, design doc §2 option A+C).
//
//  Three call sites share it: the Log Meal actions list (transcript → the search
//  field, which arms the existing ASK AI row), the staging plate's CLARIFY field,
//  and the journal note field. Every one of them is a plain `String` sink.
//
//  THE RULE THAT MATTERS: committing a transcript puts text in the caller's
//  field and *arms* the caller's confirm action. It NEVER dispatches. Every AI
//  dispatch is a paid Claude call on the user's own API key, and speech-to-text
//  errors on food nouns are the expected case, not the exception — so the user
//  reads the words before they cost anything. There is no `store` in this file
//  and there must never be one.
//
//  All branching lives in `DictationDisplayModel` (pure, unit-tested without a
//  mic). This file renders that model and owns the engine lifecycle; it does not
//  re-derive an availability or phase decision inline.
//
//  Privacy: nothing here logs the transcript (docs/development-rules.md).
//

import Foundation
import SwiftUI

// MARK: - DictationControl

struct DictationControl: View {

    // MARK: Public surface

    /// Up to ~100 short phrases biasing recognition toward the caller's domain
    /// vocabulary. Pass `[]` when there is nothing meaningful to bias with.
    let contextualStrings: [String]

    /// Bumped by the host immediately before it navigates somewhere that will
    /// take the audio route — SCAN's `AVCaptureSession`, in practice. Any change
    /// tears the session down synchronously, because `AVAudioEngine` and
    /// `AVCaptureSession` must never run at once (design doc R1). Hosts that
    /// never navigate mid-dictation leave it at the default and it is inert;
    /// `onDisappear` is the backstop, but a push can start the camera before the
    /// source view's `onDisappear` lands, so the host asks first.
    var stopToken: Int = 0

    /// Called with the FULL current transcript whenever it changes in a
    /// committed way: once when the final result lands, on every subsequent edit
    /// in the ready state, and with `""` when the user taps CLEAR. The control
    /// holds exactly one transcript at a time, so callers should treat each call
    /// as "replace whatever you last received from me".
    let onTranscript: (String) -> Void

    // MARK: Body

    var body: some View {
        let model = DictationDisplayModel.make(
            availability: availability,
            phase: phase,
            partialText: partialText,
            finalText: finalText
        )

        return VStack(alignment: .leading, spacing: DOSSpacing.xs) {
            #if targetEnvironment(simulator)
            simulatorContent(model)
            #else
            content(model)
            #endif
        }
        .animation(AnimationTokens.easeStandard, value: model)
        .onAppear { prepareEngine() }
        .onDisappear { teardown() }
        .onChange(of: scenePhase) { _, newScenePhase in
            handleScenePhase(newScenePhase)
        }
        .onChange(of: stopToken) { _, _ in
            teardown()
        }
    }

    // MARK: Private — state

    @Environment(\.scenePhase) private var scenePhase

    @State private var engine: SpeechEngine?
    /// Mirrors `engine.availability`. The protocol is not observable, so this is
    /// refreshed explicitly: at mount, after the permission prompts, and on every
    /// return to `.active` — that last one is how a user who just flipped the
    /// switch in Settings gets unblocked without relaunching.
    @State private var availability: SpeechAvailability = .needsPermission
    @State private var phase: DictationPhase = .idle
    @State private var partialText = ""
    @State private var finalText = ""
    @State private var listenTask: Task<Void, Never>?
    /// When words last landed. Drives the meter's swell; see `DictationLevelMeter`.
    @State private var lastVoiceActivity = Date()

    #if targetEnvironment(simulator)
    @State private var simulatorText = ""
    #endif

    /// Parsed once so the SETTINGS row can be *absent* rather than present and
    /// silently inert — the failure mode `BarcodeScannerView`'s camera-denial
    /// `default: break` shipped and this control exists partly to avoid.
    private var settingsURL: URL? {
        URL(string: UIApplication.openSettingsURLString)
    }

    private var isCommitted: Bool {
        if case .ready = phase { return true }
        return false
    }

    // MARK: Private — rendering

    @ViewBuilder
    private func content(_ model: DictationDisplayModel) -> some View {
        switch model.state {
        case .idle:
            speakRow(title: model.primaryActionTitle ?? "SPEAK")

        case .requestingPermission:
            panel(title: "MICROPHONE") {
                statusLine(model)
            }

        case let .listening(transcript):
            listeningPanel(transcript: transcript, model: model)

        case let .finalizing(transcript):
            finalizingPanel(transcript: transcript, model: model)

        case .ready:
            readyPanel(model)

        case .blocked:
            blockedPanel(model)

        case .unavailable:
            unavailablePanel(model)

        case let .failed(message):
            failedPanel(message: message, model: model)
        }
    }

    /// Deliberately the same shape as MANUAL / SCAN / PHOTO in
    /// `UnifiedFoodEntryView.actionsSection`: caption icon, bodySmall label, one
    /// amber `foregroundStyle` on the HStack. Voice is one more way to log, not
    /// a special guest.
    private func speakRow(title: String) -> some View {
        Button {
            startListening()
        } label: {
            HStack {
                Image(systemName: "mic")
                    .font(DOSTypography.caption)
                Text(title)
                    .font(DOSTypography.bodySmall)
            }
            .foregroundStyle(AmberTheme.amber)
        }
        .accessibilityHint("Dictate instead of typing")
    }

    private func listeningPanel(transcript: String, model: DictationDisplayModel) -> some View {
        panel(title: model.statusMessage ?? "LISTENING") {
            transcriptText(transcript, style: model.transcriptStyle)

            if model.showsLevelMeter {
                DictationLevelMeter(lastActivity: lastVoiceActivity)
            }

            HStack {
                Spacer()
                Button {
                    stopListening()
                } label: {
                    Text(model.primaryActionTitle ?? "STOP")
                        .frame(minWidth: 120, minHeight: 28)
                }
                .buttonStyle(.dosPrimary)
                .accessibilityLabel("Stop dictating")
            }
        }
    }

    private func finalizingPanel(transcript: String, model: DictationDisplayModel) -> some View {
        panel(title: "FINALIZING") {
            HStack(alignment: .firstTextBaseline, spacing: DOSSpacing.xs) {
                transcriptText(transcript, style: model.transcriptStyle, showsCursor: false)
                FiguresLoadingView.inline
            }
        }
    }

    private func readyPanel(_ model: DictationDisplayModel) -> some View {
        panel(title: model.statusMessage ?? "HEARD") {
            // An ordinary editable field, pre-filled: surgical keyboard fixes for
            // a misheard food noun, no bespoke correction UI.
            TextField("Transcript", text: transcriptBinding, axis: .vertical)
                .font(DOSTypography.bodySmall)
                .foregroundStyle(AmberTheme.amber)
                .lineLimit(1 ... 4)
                .textFieldStyle(.plain)
                .accessibilityLabel("Dictated text, editable")

            HStack {
                Button(model.primaryActionTitle ?? "CLEAR") {
                    clear()
                }
                .buttonStyle(.dosGhost)
                .accessibilityHint("Discard the dictated text")
                Spacer()
            }
        }
    }

    private func blockedPanel(_ model: DictationDisplayModel) -> some View {
        panel(title: "MICROPHONE") {
            statusLine(model)

            if model.showsSettingsRow, let settingsURL {
                Button {
                    UIApplication.shared.open(settingsURL)
                } label: {
                    HStack {
                        Image(systemName: "gear")
                            .font(DOSTypography.caption)
                        Text("SETTINGS →")
                            .font(DOSTypography.bodySmall)
                        Spacer()
                    }
                    .foregroundStyle(AmberTheme.amber)
                }
                .accessibilityHint("Open the app's settings to allow microphone access")
            }

            if model.showsKeyboardHint {
                keyboardHint
            }
        }
    }

    private func unavailablePanel(_ model: DictationDisplayModel) -> some View {
        panel(title: "DICTATION") {
            statusLine(model)

            if model.showsKeyboardHint {
                keyboardHint
            }
        }
    }

    private func failedPanel(message: String, model: DictationDisplayModel) -> some View {
        panel(title: "DICTATION") {
            statusLine(model)

            HStack {
                Button(model.primaryActionTitle ?? "TRY AGAIN") {
                    phase = .idle
                }
                .buttonStyle(.dosGhost)
                Spacer()
            }
        }
        .accessibilityLabel("Dictation failed. \(message)")
    }

    @ViewBuilder
    private func statusLine(_ model: DictationDisplayModel) -> some View {
        if let message = model.statusMessage {
            Text(message)
                .font(DOSTypography.caption)
                .foregroundStyle(model.isErrorMessage ? AmberTheme.cgaRed : AmberTheme.amberDark)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The Option-0 fallback. Once we cannot open our own mic it is the only
    /// thing left that actually works, so it is copy, not decoration.
    private var keyboardHint: some View {
        Text("TIP: THE KEYBOARD'S OWN MIC KEY STILL DICTATES INTO ANY FIELD.")
            .font(DOSTypography.caption)
            .foregroundStyle(AmberTheme.amberDark)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func transcriptText(
        _ transcript: String,
        style: DictationDisplayModel.TranscriptStyle?,
        showsCursor: Bool = true
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(transcript)
                .font(DOSTypography.bodySmall)
                .foregroundStyle(style == .committed ? AmberTheme.amber : AmberTheme.amberDark)
                .fixedSize(horizontal: false, vertical: true)

            if showsCursor, style == .provisional {
                DictationBlockCursor()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Panel chrome comes from `DOSSurfaces` — never a hand-rolled
    /// `overlay(Rectangle().stroke(...)) + background`.
    private func panel(
        title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: DOSSpacing.xs) {
            Text(title).dosHeader(AmberTheme.amber)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dosCard(.panel)
    }

    private var transcriptBinding: Binding<String> {
        Binding(
            get: { finalText },
            set: { newValue in
                finalText = newValue
                onTranscript(newValue)
            }
        )
    }

    // MARK: Private — simulator

    // The simulator cannot do speech-to-text (broken host-mic passthrough,
    // repeated in-simulator SFSpeechRecognizer failures), so this mirrors
    // `BarcodeScannerView`'s simulator branch: type what you would have said,
    // then run the SAME commit path. That keeps the whole downstream flow —
    // commit → ASK AI → staging plate → SCAN — exercisable under xcodebuild.
    #if targetEnvironment(simulator)
    @ViewBuilder
    private func simulatorContent(_ model: DictationDisplayModel) -> some View {
        if case .ready = model.state {
            content(model)
        } else {
            simulatorFallback
        }
    }

    private var simulatorFallback: some View {
        VStack(alignment: .leading, spacing: DOSSpacing.xs) {
            Text("SPEECH UNAVAILABLE IN SIMULATOR").dosHeader(AmberTheme.amber)

            HStack(spacing: DOSSpacing.xs) {
                TextField("Type what you would say", text: $simulatorText)
                    .font(DOSTypography.bodySmall)
                    .textFieldStyle(.roundedBorder)

                Button("COMMIT") {
                    let spoken = simulatorText
                    simulatorText = ""
                    commit(spoken)
                }
                .font(DOSTypography.bodySmall)
                .foregroundStyle(AmberTheme.amber)
                .disabled(simulatorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dosCard(.panel)
    }
    #endif

    // MARK: Private — engine lifecycle

    @MainActor
    private func prepareEngine() {
        let resolved = engine ?? makeSpeechEngine()
        engine = resolved
        availability = resolved.availability
    }

    @MainActor
    private func handleScenePhase(_ newScenePhase: ScenePhase) {
        guard newScenePhase == .active else {
            // `UIBackgroundModes: audio` is already declared for the sensor
            // stack, so a leaked record session is an app that is genuinely
            // listening in the background. Never leave one behind.
            teardown()
            return
        }
        refreshAvailability()
    }

    @MainActor
    private func refreshAvailability() {
        guard let engine else { return }
        availability = engine.availability
        guard availability != .available, availability != .needsPermission else { return }
        // Permission was revoked while we sat on screen: stop claiming to listen.
        teardown()
    }

    @MainActor
    private func startListening() {
        guard let engine else { return }

        switch engine.availability {
        case .available:
            beginSession(engine)

        case .needsPermission:
            phase = .requestingPermission
            Task {
                let resolved = await engine.requestAuthorization()
                availability = resolved
                guard resolved == .available else {
                    // The explanatory copy is the model's job; the phase only has
                    // to stop claiming a prompt is on screen.
                    phase = .idle
                    return
                }
                beginSession(engine)
            }

        case .denied, .restricted, .unsupportedLocale:
            // Not reachable from a rendered mic (the model hides it), but a
            // revocation can race the tap. Re-sync and let the model re-render.
            availability = engine.availability
            phase = .idle
        }
    }

    @MainActor
    private func beginSession(_ engine: SpeechEngine) {
        listenTask?.cancel()
        partialText = ""
        finalText = ""
        lastVoiceActivity = Date()
        phase = .listening

        let stream = engine.start(contextualStrings: contextualStrings)
        listenTask = Task {
            do {
                for try await transcript in stream {
                    guard !Task.isCancelled else { return }
                    if transcript.isFinal {
                        commit(transcript.text)
                    } else {
                        partialText = transcript.text
                        lastVoiceActivity = Date()
                    }
                }
                guard !Task.isCancelled else { return }
                // The stream finished without an explicit final result (a normal
                // stop, or an interruption). Keep whatever was heard — throwing
                // away the words the user already said is the worst possible
                // response to being interrupted.
                if !isCommitted {
                    commit(partialText)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(Self.describe(error))
            }
        }
    }

    @MainActor
    private func stopListening() {
        guard let engine else { return }
        // Commit, not abandon: stop capturing but let the recognizer deliver.
        phase = .finalizing
        engine.stop()
    }

    @MainActor
    private func teardown() {
        listenTask?.cancel()
        listenTask = nil
        engine?.cancel()
        partialText = ""

        switch phase {
        case .requestingPermission, .listening, .finalizing:
            phase = .idle
        case .idle, .ready, .failed:
            // A committed transcript survives backgrounding — it is already in
            // the caller's field, and collapsing the panel would be a lie.
            break
        }
    }

    @MainActor
    private func clear() {
        listenTask?.cancel()
        listenTask = nil
        engine?.cancel()
        partialText = ""
        finalText = ""
        phase = .idle
        onTranscript("")
    }

    private func commit(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        partialText = ""
        finalText = trimmed

        guard !trimmed.isEmpty else {
            // Nothing heard. Emitting "" here would wipe a field the user may
            // have typed into — the worst possible response to a failed
            // recognition. Just fall back to idle so SPEAK can be tapped again.
            phase = .idle
            return
        }

        phase = .ready
        onTranscript(trimmed)
    }

    private static func describe(_ error: Error) -> String {
        guard let speechError = error as? SpeechEngineError else {
            return "Dictation failed"
        }
        switch speechError {
        case .audioSessionFailed: return "Microphone unavailable"
        case .recognitionFailed: return "Could not understand that"
        case .interrupted: return "Dictation interrupted"
        case .unavailable: return "Dictation unavailable"
        }
    }
}

// MARK: - Block cursor

/// The blinking block cursor that marks provisional text. `AnimationTokens.blink`
/// exists for exactly this.
private struct DictationBlockCursor: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var visible = true

    var body: some View {
        Text("█")
            .font(DOSTypography.bodySmall)
            .foregroundStyle(AmberTheme.amber)
            .opacity(visible ? 1 : 0)
            .onAppear {
                // Reduce Motion keeps a steady cursor rather than a still-but-
                // invisible one: the caret still marks the insertion point.
                guard !reduceMotion else { return }
                withAnimation(AnimationTokens.blink) {
                    visible = false
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Level meter

/// Block-glyph activity meter.
///
/// The `SpeechEngine` seam is a TEXT seam — it exposes no audio power — so this
/// is honestly an activity indicator, not a calibrated VU meter: it swells when
/// new words land and settles to a low hum otherwise. That is the signal the
/// user actually needs ("it is hearing me"), and it keeps the engine protocol
/// from growing an audio-level API it would otherwise only need for decoration.
/// Never a `ProgressView()` — StyleGuard rule 6, and it would look wrong anyway.
private struct DictationLevelMeter: View {
    let lastActivity: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let columns = 18
    private static let glyphs: [Character] = [" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
    private static let tickInterval: Double = 0.12

    var body: some View {
        Group {
            if reduceMotion {
                Text(String(repeating: "▄", count: Self.columns))
            } else {
                TimelineView(.animation(minimumInterval: Self.tickInterval, paused: false)) { context in
                    Text(Self.bars(at: context.date, lastActivity: lastActivity))
                }
            }
        }
        .font(DOSTypography.mono(size: 14))
        .foregroundStyle(AmberTheme.amber)
        .accessibilityHidden(true)
    }

    private static func bars(at date: Date, lastActivity: Date) -> String {
        let sinceVoice = date.timeIntervalSince(lastActivity)
        let energy = 0.35 + 0.65 * max(0, 1 - sinceVoice / 1.5)
        let tick = date.timeIntervalSinceReferenceDate / tickInterval

        var row = ""
        for column in 0 ..< columns {
            let wave = sin(tick * 0.9 + Double(column) * 0.7)
                + sin(tick * 0.37 + Double(column) * 1.9)
            let normalized = min(max((wave + 2) / 4, 0), 1)
            let index = min(max(Int(normalized * energy * Double(glyphs.count - 1)), 0), glyphs.count - 1)
            row.append(glyphs[index])
        }
        return row
    }
}
