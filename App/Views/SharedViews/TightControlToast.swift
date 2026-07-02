//
//  TightControlToast.swift
//  DOSBTS
//
//  U4 (DMNC-772): the transient "TIGHT CONTROL" celebration toast. Mirrors the
//  LoggedMealToast controller/overlay pattern but is hoisted to ContentView scope
//  (never inside a sheet) and anchored clear of the per-tab GlucoseStatusBar.
//  Visual + VoiceOver always present; sound + haptic only when `withFeedback`
//  (night-gated by the middleware, R10/R6). Reduce-motion collapses the slide to
//  an opacity change (R12).
//

import SwiftUI

// MARK: - Display model

/// Pure headline/sub-line derivation from a celebration payload. Extracted so the
/// copy rules are unit-testable without instantiating the view.
struct TightControlToastModel: Equatable {
    let headline: String
    let subline: String?

    init(_ celebration: TightControlCelebration) {
        headline = celebration.count > 1 ? "TIGHT CONTROL ×\(celebration.count)" : "TIGHT CONTROL"
        if let hours = celebration.hours {
            subline = "\(hours) HOURS IN RANGE"
        } else {
            // Consolidated ×N (count > 1) or a retroactively-drained single streak.
            subline = nil
        }
    }
}

// MARK: - Reveal

enum TightControlToastReveal {
    /// Reduce-motion collapses the staged slide to an immediate opacity change (R12).
    static func usesStaticReveal(reduceMotion: Bool) -> Bool { reduceMotion }

    static func transition(reduceMotion: Bool) -> AnyTransition {
        usesStaticReveal(reduceMotion: reduceMotion)
            ? .opacity
            : .move(edge: .bottom).combined(with: .opacity)
    }

    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.25)
    }
}

// MARK: - View

struct TightControlToastView: View {
    let celebration: TightControlCelebration
    let onTap: () -> Void

    private var model: TightControlToastModel { TightControlToastModel(celebration) }

    var body: some View {
        VStack(spacing: DOSSpacing.xs) {
            Text(model.headline)
                .font(DOSTypography.displayMedium)
                .foregroundColor(AmberTheme.amberLight)

            if let subline = model.subline {
                Text(subline)
                    .font(DOSTypography.bodySmall)
                    .foregroundColor(AmberTheme.cgaCyan)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.vertical, DOSSpacing.md)
        .padding(.horizontal, DOSSpacing.lg)
        .dosCard(.toast, stroke: AmberTheme.cgaCyan, padding: nil)
        .shadow(color: AmberTheme.cgaCyan.opacity(0.6), radius: 8) // phosphor glow
        .padding(.horizontal, DOSSpacing.lg)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Controller

/// Show/dismiss lifecycle for the celebration toast: 4s auto-dismiss, re-show replaces
/// content and resets the timer. Plays the audible/tactile/VoiceOver channels on show;
/// the presenting view owns the visual transition (`.animation(_:value:)` on the overlay).
@MainActor
final class TightControlToastController: ObservableObject {
    static let autoDismissDelay: TimeInterval = 4.0
    static let feedbackVolume: Float = 0.5

    @Published private(set) var celebration: TightControlCelebration?

    private var workItem: DispatchWorkItem?

    func show(_ celebration: TightControlCelebration) {
        self.celebration = celebration
        workItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.dismiss() }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoDismissDelay, execute: item)

        // VoiceOver gets the same signal as the visual/audio channels, regardless of
        // night (it is the accessibility equivalent of the visible toast, R12).
        UIAccessibility.post(notification: .announcement, argument: Self.announcement(for: celebration))

        // Sound + haptic only when the middleware allowed feedback (not night, R10).
        // playSound respects the device mute switch (R6).
        if celebration.withFeedback {
            DirectNotifications.shared.playSound(sound: .achievement, volume: Self.feedbackVolume)
            DirectNotifications.shared.hapticNotification(.success)
        }
    }

    func dismiss() {
        workItem?.cancel()
        workItem = nil
        celebration = nil
    }

    nonisolated static func announcement(for celebration: TightControlCelebration) -> String {
        let model = TightControlToastModel(celebration)
        return [model.headline, model.subline].compactMap { $0 }.joined(separator: ", ")
    }
}
