//
//  SFSpeechEngine.swift
//  DOSBTS
//
//  The V1 `SpeechEngine`: `SFSpeechRecognizer` + `AVAudioEngine` +
//  `SFSpeechAudioBufferRecognitionRequest` (DMNC-1486, decisions D4/D5).
//
//  Why this and not `SpeechAnalyzer`/`SpeechTranscriber`: `contextualStrings`.
//  Biasing recognition toward the foods this user has actually logged is the
//  single highest-leverage quality lever available for food nouns and brand
//  names, and the new API does not accept contextual strings at all. See
//  `docs/plans/2026-08-09-voice-v1-design-options.md` §1 D5.
//
//  Recognition is on-device only (`requiresOnDeviceRecognition = true`) — D4.
//  Privacy by design, and it keeps us off the device-wide 1000-requests/hour
//  quota that the server path shares with every other app on the phone.
//
//  ## Never log recognized text
//
//  Not via `DirectLog`, not in an error message, not in a comment example.
//  `docs/development-rules.md`. Every log line in this file is a fixed literal.
//
//  ## Audio session ownership is a SAFETY concern, not a tidiness one
//
//  A low-glucose alarm can fire while the mic is open.
//  `DirectNotifications.playSound` sets `.playback` + `.mixWithOthers` and
//  `setActive(true)` on every alarm and never deactivates. So:
//
//  - We take `.playAndRecord` with `[.mixWithOthers, .defaultToSpeaker]`.
//    Never `.duckOthers`, never exclusive access — an inaudible alarm is a
//    safety regression, not a cosmetic one.
//  - We deactivate only a session *we* activated, and never on `ReadAloud`'s
//    or `DirectNotifications`' behalf.
//  - If the alarm takes the session category away from us mid-utterance, the
//    alarm wins: we commit what we already heard and get out of the way.
//

import AVFAudio
import AVFoundation
import Foundation
import Speech

// MARK: - SFSpeechEngine

@MainActor
final class SFSpeechEngine: SpeechEngine {
    // MARK: Internal

    /// Read on every SwiftUI render, so the expensive half — constructing an
    /// `SFSpeechRecognizer` — is memoized behind `resolvedRecognizer()`.
    /// The permission reads themselves are cheap property lookups.
    var availability: SpeechAvailability {
        resolveAvailability()
    }

    /// Microphone first, then speech. Returns the re-resolved availability.
    ///
    /// This is also the app's "re-check" entry point (first mic tap, and again
    /// on return from Settings), so it always invalidates the memoized
    /// recognizer first — `isAvailable` can flip once on-device assets land.
    func requestAuthorization() async -> SpeechAvailability {
        invalidateRecognizer()

        let current = resolveAvailability()
        // Already granted, already denied, or restricted: never re-prompt.
        // `.restricted` (MDM / Screen Time) in particular is not retryable and
        // must never be offered a retry.
        guard current == .needsPermission else {
            return current
        }

        if AVAudioApplication.shared.recordPermission == .undetermined {
            let micGranted = await AVAudioApplication.requestRecordPermission()
            guard micGranted else {
                // No point putting a second system prompt in front of someone
                // who just said no to the first one.
                invalidateRecognizer()
                return resolveAvailability()
            }
        }

        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            _ = await Self.requestSpeechAuthorization()
        }

        invalidateRecognizer()
        return resolveAvailability()
    }

    func start(contextualStrings: [String]) -> AsyncThrowingStream<SpeechTranscript, Error> {
        // Defensive teardown: a second `start` while one is live would otherwise
        // orphan the first `AVAudioEngine` and — far worse — its input tap. A
        // leaked tap plus this app's `UIBackgroundModes: audio` is an app that
        // is genuinely listening in the background.
        releaseEverything()
        finishStream()

        // Fresh generation. Every deferred callback (recognition hop, watchdog,
        // notification observer, stream termination) carries this token and
        // no-ops if a newer session has started since it was scheduled.
        sessionToken &+= 1
        let token = sessionToken

        // Re-resolve rather than trusting the render-path cache: this runs once
        // per mic tap, which is cheap, and it makes `.unavailable` honest.
        invalidateRecognizer()

        return AsyncThrowingStream<SpeechTranscript, Error> { continuation in
            let availability = self.resolveAvailability()

            guard availability == .available, let recognizer = self.resolvedRecognizer() else {
                continuation.finish(throwing: SpeechEngineError.unavailable(availability))
                return
            }

            self.continuation = continuation

            continuation.onTermination = { [weak self] _ in
                // An abandoned stream (view dismissed mid-utterance) has to tear
                // the engine down. Token-scoped so an *earlier* stream's
                // termination can never kill a *later* session.
                Task { @MainActor in
                    self?.cancelIfCurrent(token: token)
                }
            }

            do {
                try self.beginCapture(recognizer: recognizer, contextualStrings: contextualStrings)
            } catch {
                self.releaseEverything()
                self.finishStream(throwing: error)
            }
        }
    }

    /// Commit. Stops capturing audio but lets the recognizer deliver its final
    /// result; the stream finishes, it does not throw.
    func stop() {
        guard phase == .capturing else {
            return
        }

        phase = .finishing
        stopAudioCapture()
        request?.endAudio()
        startFinalResultGrace()
    }

    /// Abandon. Tears everything down immediately and discards pending results.
    func cancel() {
        releaseEverything()
        finishStream()
    }

    // MARK: Private

    private enum Phase {
        /// Nothing running.
        case idle
        /// Mic open, partials flowing.
        case capturing
        /// `endAudio()` sent, waiting for the recognizer's final result.
        case finishing
    }

    /// `SFSpeechRecognizer` refuses more than ~60 s of audio per request. Stop
    /// at 55 s so the commit is ours and the user gets their words, rather than
    /// the framework's error and nothing.
    private static let maxCaptureDuration: TimeInterval = 55

    /// Auto-stop after this much dead air. A safety net, not the commit gesture
    /// — the user taps STOP. Stopping never dispatches anything, so a spurious
    /// auto-stop costs nothing.
    private static let silenceTimeout: TimeInterval = 15

    /// How long to wait for a final result after `endAudio()` before committing
    /// the last partial ourselves. Without this the UI can hang in `finalizing`.
    private static let finalResultGrace: Duration = .seconds(3)

    private static let watchdogTick: Duration = .milliseconds(250)
    private static let tapBus: AVAudioNodeBus = 0
    private static let tapBufferSize: AVAudioFrameCount = 1024

    private var phase: Phase = .idle
    private var sessionToken = 0

    private var audioEngine: AVAudioEngine?
    private var tappedNode: AVAudioInputNode?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var continuation: AsyncThrowingStream<SpeechTranscript, Error>.Continuation?

    /// One at a time: the capture watchdog during `.capturing`, the final-result
    /// grace timer during `.finishing`.
    private var timerTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    private var didActivateSession = false
    private var latestText = ""
    private var captureStartedAt = Date()
    private var lastResultAt = Date()

    private var cachedRecognizer: SFSpeechRecognizer?
    private var recognizerResolved = false

    // MARK: - Availability

    private func resolveAvailability() -> SpeechAvailability {
        let speech = SFSpeechRecognizer.authorizationStatus()
        let mic = AVAudioApplication.shared.recordPermission

        // Not reversible by the user, so the UI must never offer a retry.
        if speech == .restricted {
            return .restricted
        }

        if speech == .denied || mic == .denied {
            return .denied
        }

        // Deliberately resolved before any recognizer work: `isAvailable` is
        // false while speech authorization is undetermined, so probing the
        // recognizer first would memoize a permanent `.unsupportedLocale` for a
        // device that is merely un-asked.
        guard speech == .authorized, mic == .granted else {
            return .needsPermission
        }

        return resolvedRecognizer() == nil ? .unsupportedLocale : .available
    }

    private func resolvedRecognizer() -> SFSpeechRecognizer? {
        if recognizerResolved {
            return cachedRecognizer
        }

        recognizerResolved = true
        cachedRecognizer = Self.makeRecognizer(for: Locale.current)
            ?? Self.makeRecognizer(for: Locale(identifier: "en-US"))

        if cachedRecognizer == nil {
            DirectLog.info("Voice, no on-device speech recognizer for this locale")
        }

        return cachedRecognizer
    }

    private func invalidateRecognizer() {
        recognizerResolved = false
        cachedRecognizer = nil
    }

    private static func makeRecognizer(for locale: Locale) -> SFSpeechRecognizer? {
        guard let candidate = SFSpeechRecognizer(locale: locale) else {
            return nil
        }
        // On-device only (D4). A recognizer that would have to phone home is
        // treated as no recognizer at all — we never silently route microphone
        // audio to a server.
        guard candidate.supportsOnDeviceRecognition, candidate.isAvailable else {
            return nil
        }
        return candidate
    }

    private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            // `requestAuthorization` documents one callback, but a checked
            // continuation is *fatal* on a double resume and this handler
            // arrives on an arbitrary queue. Guard it — same lesson as
            // docs/solutions/logic-errors/combine-future-async-bridge-double-resume-20260420.md
            let guardBox = OneShotGuard()
            SFSpeechRecognizer.requestAuthorization { status in
                guard guardBox.claim() else {
                    return
                }
                continuation.resume(returning: status)
            }
        }
    }

    // MARK: - Capture

    private func beginCapture(recognizer: SFSpeechRecognizer, contextualStrings: [String]) throws {
        try activateAudioSession()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = false
        // Straight through from the caller — the user's own logged food names.
        request.contextualStrings = contextualStrings

        let audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: Self.tapBus)

        // A zero-channel / zero-rate format means the session never actually
        // handed us an input route. `installTap` raises an unrecoverable
        // Objective-C exception on such a format rather than throwing, so this
        // has to be checked before the tap, not after.
        guard format.channelCount > 0, format.sampleRate > 0 else {
            deactivateSessionIfOwned()
            DirectLog.error("Voice, audio input format has no channels")
            throw SpeechEngineError.audioSessionFailed
        }

        inputNode.installTap(onBus: Self.tapBus, bufferSize: Self.tapBufferSize, format: format) { buffer, _ in
            // Realtime audio thread. Appending buffers is the only thing that
            // happens here.
            request.append(buffer)
        }
        tappedNode = inputNode

        audioEngine.prepare()

        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: Self.tapBus)
            tappedNode = nil
            deactivateSessionIfOwned()
            DirectLog.error("Voice, could not start the audio engine", error: error)
            throw SpeechEngineError.audioSessionFailed
        }

        self.request = request
        self.audioEngine = audioEngine
        latestText = ""
        captureStartedAt = Date()
        lastResultAt = captureStartedAt
        phase = .capturing

        let token = sessionToken
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            // Off the main actor. Flatten to plain values here so no
            // non-Sendable reference crosses the hop.
            //
            // `text` is the user's speech. It goes to the stream and nowhere
            // else — never to `DirectLog`.
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil

            Task { @MainActor in
                self?.handleRecognition(token: token, text: text, isFinal: isFinal, failed: failed)
            }
        }

        addSessionObservers(token: token)
        startCaptureWatchdog(token: token)
    }

    private func handleRecognition(token: Int, text: String?, isFinal: Bool, failed: Bool) {
        // The recognition handler fires repeatedly and can fire again after an
        // error or after we have already torn down. Both guards matter.
        guard token == sessionToken, phase != .idle else {
            return
        }

        if let text {
            latestText = text
            lastResultAt = Date()
        }

        if isFinal {
            deliverFinalAndFinish()
            return
        }

        if failed {
            // Throwing away words the user already said is the worst possible
            // response to a hiccup, so anything already recognized commits as
            // if the user had tapped STOP. Only a failure with nothing at all
            // to show surfaces as an error.
            if latestText.isEmpty {
                DirectLog.error("Voice, recognition failed before any speech was recognized")
                releaseEverything()
                finishStream(throwing: SpeechEngineError.recognitionFailed)
            } else {
                deliverFinalAndFinish()
            }
            return
        }

        if let text {
            yield(SpeechTranscript(text: text, isFinal: false))
        }
    }

    /// Commit whatever we have and close the stream. Never throws — this is the
    /// path an interruption, a lost route and the watchdogs all end on.
    private func deliverFinalAndFinish() {
        let text = latestText
        releaseEverything()
        yield(SpeechTranscript(text: text, isFinal: true))
        finishStream()
    }

    /// - Parameter sessionTakenOver: `true` when someone else — the alarm
    ///   player, ReadAloud, Siri, a phone call — now owns the audio session.
    ///   We then drop our ownership claim *without* deactivating, because
    ///   `setActive(false)` against a session another client is actively
    ///   playing through is the one way this code could silence a low-glucose
    ///   alarm. In practice iOS refuses that deactivation with a busy error
    ///   while I/O is running, but "in practice" is not a safety argument.
    ///   Not owning it is.
    private func endGracefully(reason: StaticString, sessionTakenOver: Bool = false) {
        guard phase != .idle else {
            return
        }

        if sessionTakenOver {
            didActivateSession = false
        }

        // `reason` is a compile-time literal by type. Nothing spoken can reach
        // a log line through here.
        DirectLog.info("Voice, ending dictation early: \(reason)")
        deliverFinalAndFinish()
    }

    // MARK: - Timers

    private func startCaptureWatchdog(token: Int) {
        timerTask?.cancel()
        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.watchdogTick)

                guard !Task.isCancelled, let self, self.sessionToken == token, self.phase == .capturing else {
                    return
                }

                let now = Date()

                if now.timeIntervalSince(self.captureStartedAt) >= Self.maxCaptureDuration {
                    DirectLog.info("Voice, hit the per-request duration ceiling")
                    self.stop()
                    return
                }

                if now.timeIntervalSince(self.lastResultAt) >= Self.silenceTimeout {
                    DirectLog.info("Voice, auto-stopping after silence")
                    self.stop()
                    return
                }
            }
        }
    }

    private func startFinalResultGrace() {
        timerTask?.cancel()
        timerTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.finalResultGrace)

            guard !Task.isCancelled, let self, self.phase == .finishing else {
                return
            }

            // The recognizer never produced a final result. Commit the last
            // partial rather than stranding the UI in `finalizing` forever.
            DirectLog.info("Voice, no final result arrived; committing the last partial")
            self.deliverFinalAndFinish()
        }
    }

    // MARK: - Audio session

    private func activateAudioSession() throws {
        let session = AVAudioSession.sharedInstance()

        do {
            // `.mixWithOthers`, never `.duckOthers`: a low-glucose alarm can
            // fire while the mic is open and `DirectNotifications.playSound`
            // has to stay audible at the configured volume.
            //
            // `.defaultToSpeaker` because `.playAndRecord` otherwise routes
            // playback to the earpiece — which would make that same alarm a
            // whisper.
            //
            // Mode stays `.default`. `.measurement` is the usual recommendation
            // for recognition accuracy, but it attenuates playback output on
            // some devices, which is the same safety problem by another route.
            try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker])
            try session.setActive(true)
            didActivateSession = true
        } catch {
            DirectLog.error("Voice, could not configure the audio session", error: error)
            throw SpeechEngineError.audioSessionFailed
        }
    }

    private func deactivateSessionIfOwned() {
        guard didActivateSession else {
            return
        }
        didActivateSession = false

        do {
            // `.notifyOthersOnDeactivation` is only meaningful when the first
            // argument is `false`.
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Another client in this process (the alarm player, ReadAloud) is
            // still using the session. That is a benign refusal and we never
            // force it — the alarm outranks dictation.
            DirectLog.info("Voice, audio session stayed active on deactivate")
        }
    }

    private func addSessionObservers(token: Int) {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            // Read out of the notification here; nothing non-Sendable crosses
            // the hop.
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt

            Task { @MainActor in
                guard let self, self.sessionToken == token else {
                    return
                }
                guard let rawType, AVAudioSession.InterruptionType(rawValue: rawType) == .began else {
                    return
                }
                // A call, Siri, or an alarm took the mic. Keep the words, and
                // leave the session alone — the system has already taken it.
                self.endGracefully(reason: "audio session interrupted", sessionTakenOver: true)
            }
        })

        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt

            Task { @MainActor in
                guard let self, self.sessionToken == token else {
                    return
                }
                guard let rawReason, let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) else {
                    return
                }

                switch reason {
                case .oldDeviceUnavailable:
                    // AirPods pulled out, dock removed — the input we were
                    // recording from is gone.
                    self.endGracefully(reason: "input route lost")

                case .categoryChange:
                    // `DirectNotifications.playSound` sets `.playback` on every
                    // alarm, which takes the input away from us. The alarm wins:
                    // commit what we heard instead of fighting it for the
                    // session. Our own category set at capture start leaves the
                    // category as `.playAndRecord`, so this never self-triggers.
                    if AVAudioSession.sharedInstance().category != .playAndRecord {
                        self.endGracefully(
                            reason: "session category changed away from recording",
                            sessionTakenOver: true
                        )
                    }

                default:
                    break
                }
            }
        })
    }

    private func removeSessionObservers() {
        let center = NotificationCenter.default
        for observer in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
    }

    // MARK: - Teardown

    /// Stop the microphone and hand the audio session back. Idempotent, and
    /// safe on every path including the error ones — the tap in particular must
    /// come off no matter how we got here.
    private func stopAudioCapture() {
        timerTask?.cancel()
        timerTask = nil

        removeSessionObservers()

        tappedNode?.removeTap(onBus: Self.tapBus)
        tappedNode = nil

        audioEngine?.stop()
        audioEngine = nil

        deactivateSessionIfOwned()
    }

    /// Everything `stopAudioCapture` does, plus the recognizer. Idempotent.
    private func releaseEverything() {
        stopAudioCapture()

        recognitionTask?.cancel()
        recognitionTask = nil
        request = nil

        latestText = ""
        phase = .idle
    }

    private func cancelIfCurrent(token: Int) {
        guard token == sessionToken else {
            return
        }
        cancel()
    }

    // MARK: - Stream

    private func yield(_ transcript: SpeechTranscript) {
        continuation?.yield(transcript)
    }

    /// Double-finish guard: nil-ing the continuation first means a late
    /// recognition callback, a watchdog and a stream termination can all race
    /// to close the same stream without any of them finishing it twice.
    private func finishStream(throwing error: (any Error)? = nil) {
        guard let continuation else {
            return
        }
        self.continuation = nil
        continuation.finish(throwing: error)
    }
}

// MARK: - OneShotGuard

/// Thread-safe "has this fired yet" latch for a completion handler that must
/// resume a checked continuation exactly once.
private final class OneShotGuard: @unchecked Sendable {
    // MARK: Internal

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if claimed {
            return false
        }
        claimed = true
        return true
    }

    // MARK: Private

    private let lock = NSLock()
    private var claimed = false
}
