//
//  HoldToCommitProgress.swift
//  DOSBTS
//
//  Press-and-hold commit control (DMNC-796). Tap fires `onTap` (typically a
//  staging route); holding past `holdDuration` fills a countdown overlay and
//  fires `onCommit` exactly once. Releasing early — or starting a scroll —
//  cancels with no commit. The fill is the confirmation: no hidden
//  affordance, no accidental commit.
//
//  Implementation note: this is a Button with a press-tracking style, NOT a
//  LongPressGesture. A long-press recognizer starves the enclosing
//  ScrollView/List pan gesture and makes the row unscrollable; Buttons
//  cooperate with scroll-view touch handling natively (drag cancels the
//  press), which is exactly the cancel-on-scroll semantic we want.
//

import SwiftUI

struct HoldToCommitProgress<Content: View>: View {
    /// Single shared hold threshold for every hold surface (R8). Tune on device.
    static var holdDuration: TimeInterval { 0.8 }

    var tint: Color = AmberTheme.amber
    let onTap: () -> Void
    let onCommit: () -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var fillProgress: Double = 0
    @State private var committedAt: Date?
    // One-shot per-press flag: the commit fires at the threshold while the
    // finger is still down, and the subsequent touch-up triggers the Button
    // action. The flag (cleared when a new press begins) suppresses it; the
    // committedAt wall-clock window is a fallback so a missed press event
    // can never permanently swallow real taps.
    @State private var didCommitDuringPress = false
    // Fires commit when the press survives the full hold duration.
    @State private var commitTask: Task<Void, Never>?
    // Reduce Motion: discrete steps instead of an animated fill.
    @State private var stepTask: Task<Void, Never>?

    var body: some View {
        Button(action: handleTap) {
            content()
                .overlay(fillOverlay)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressTrackingButtonStyle(onPressingChanged: handlePressingChanged))
        .onDisappear {
            commitTask?.cancel()
            commitTask = nil
            stepTask?.cancel()
            stepTask = nil
        }
        .accessibilityAction(named: "Log immediately") {
            // Suppression window guards rapid double activation of the
            // custom action from minting duplicate entries.
            guard !Self.shouldSuppressTap(now: Date(), committedAt: committedAt) else { return }
            commit()
        }
    }

    // MARK: - Press lifecycle

    private func handlePressingChanged(_ pressing: Bool) {
        if pressing {
            didCommitDuringPress = false
            beginFill()
            commitTask?.cancel()
            commitTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(Self.holdDuration))
                guard !Task.isCancelled else { return }
                commit()
            }
        } else {
            commitTask?.cancel()
            commitTask = nil
            cancelFill()
        }
    }

    private func handleTap() {
        if didCommitDuringPress {
            didCommitDuringPress = false
            return
        }
        guard !Self.shouldSuppressTap(now: Date(), committedAt: committedAt) else { return }
        onTap()
    }

    // MARK: - Pure helpers (unit-tested)

    /// Elapsed → 0...1 fill fraction, clamped. Non-positive duration counts as full.
    static func progress(elapsed: TimeInterval, duration: TimeInterval) -> Double {
        guard duration > 0 else { return 1 }
        return min(max(elapsed / duration, 0), 1)
    }

    static func shouldCommit(elapsed: TimeInterval, duration: TimeInterval) -> Bool {
        elapsed >= duration
    }

    /// Taps landing within a short window after a hold-commit are the
    /// touch-up of that same press, not a new intent.
    static func shouldSuppressTap(now: Date, committedAt: Date?, window: TimeInterval = 1.0) -> Bool {
        guard let committedAt else { return false }
        return now.timeIntervalSince(committedAt) < window
    }

    // MARK: - Fill lifecycle

    @ViewBuilder
    private var fillOverlay: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(tint.opacity(0.35))
                .frame(width: geometry.size.width * fillProgress)
        }
        .allowsHitTesting(false)
    }

    private func beginFill() {
        if reduceMotion {
            // Non-animated stepped progress; the commit threshold is owned by
            // commitTask, so timing is identical (R7).
            let stepInterval = Self.holdDuration / 4
            stepTask?.cancel()
            stepTask = Task { @MainActor in
                for step in 1...4 {
                    try? await Task.sleep(for: .seconds(stepInterval))
                    guard !Task.isCancelled else { return }
                    fillProgress = Self.progress(elapsed: Double(step) * stepInterval, duration: Self.holdDuration)
                }
            }
        } else {
            withAnimation(AnimationTokens.gestureProgress(duration: Self.holdDuration)) {
                fillProgress = 1
            }
        }
    }

    private func cancelFill() {
        stepTask?.cancel()
        stepTask = nil
        withAnimation(reduceMotion ? nil : AnimationTokens.easeSnap) {
            fillProgress = 0
        }
    }

    private func commit() {
        committedAt = Date()
        didCommitDuringPress = true
        DirectNotifications.shared.hapticFeedback(.medium)
        onCommit()
        cancelFill()
    }
}

// MARK: - PressTrackingButtonStyle

/// Reports press state changes; renders the label unstyled (the hold fill is
/// the press feedback, so the default opacity flash is intentionally absent).
private struct PressTrackingButtonStyle: ButtonStyle {
    let onPressingChanged: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                onPressingChanged(pressed)
            }
    }
}

// MARK: - Previews

#Preview("Idle chip") {
    HoldToCommitProgress(
        onTap: {},
        onCommit: {}
    ) {
        Text("milk 12g")
            .font(DOSTypography.caption)
            .foregroundColor(AmberTheme.amber)
            .padding(.horizontal, DOSSpacing.sm)
            .padding(.vertical, DOSSpacing.xs)
            .background(Color.black)
            .overlay(Rectangle().stroke(AmberTheme.amber, lineWidth: 1))
    }
    .padding()
    .background(Color.black)
}
