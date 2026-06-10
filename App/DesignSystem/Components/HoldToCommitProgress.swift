//
//  HoldToCommitProgress.swift
//  DOSBTS
//
//  Press-and-hold commit control (DMNC-796). Tap fires `onTap` (typically a
//  staging route); holding past `holdDuration` fills a countdown overlay and
//  fires `onCommit` exactly once. Releasing early — or a scroll drag that
//  steals the gesture — cancels with no commit. The fill is the confirmation:
//  no hidden affordance, no accidental commit.
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

    @GestureState private var isPressing = false
    @State private var fillProgress: Double = 0
    @State private var committedAt: Date?
    // One-shot per-gesture flag: a finger-down past the threshold commits via
    // the long press, but the subsequent touch-up can still register as a tap.
    // The flag (cleared when a new press begins) suppresses it regardless of
    // how long the user kept holding; the committedAt wall-clock window is a
    // fallback so a missed tap event can never permanently swallow real taps.
    @State private var didCommitDuringPress = false
    // Reduce Motion: discrete steps driven by a cancellable task instead of an
    // animated fill (async/await per repo rules; cancellation covers dismissal).
    @State private var stepTask: Task<Void, Never>?

    var body: some View {
        content()
            .overlay(fillOverlay)
            .contentShape(Rectangle())
            .onTapGesture(perform: handleTap)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: Self.holdDuration)
                    .updating($isPressing) { current, state, _ in state = current }
                    .onEnded { _ in commit() }
            )
            .onChange(of: isPressing) { _, pressing in
                if pressing {
                    didCommitDuringPress = false
                    beginFill()
                } else {
                    cancelFill()
                }
            }
            .onDisappear {
                stepTask?.cancel()
                stepTask = nil
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onTap() }
            .accessibilityAction(named: "Log immediately") {
                // Same suppression window guards rapid double activation of
                // the custom action from minting duplicate entries.
                guard !Self.shouldSuppressTap(now: Date(), committedAt: committedAt) else { return }
                commit()
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
    /// touch-up of that same gesture, not a new intent.
    static func shouldSuppressTap(now: Date, committedAt: Date?, window: TimeInterval = 1.0) -> Bool {
        guard let committedAt else { return false }
        return now.timeIntervalSince(committedAt) < window
    }

    // MARK: - Fill lifecycle

    @ViewBuilder
    private var fillOverlay: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 2)
                .fill(tint.opacity(0.35))
                .frame(width: geometry.size.width * fillProgress)
        }
        .allowsHitTesting(false)
    }

    private func beginFill() {
        if reduceMotion {
            // Non-animated stepped progress; the commit threshold is still
            // owned by the gesture, so timing is identical (R7).
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
            withAnimation(.linear(duration: Self.holdDuration)) {
                fillProgress = 1
            }
        }
    }

    private func cancelFill() {
        stepTask?.cancel()
        stepTask = nil
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
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
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(AmberTheme.amber, lineWidth: 1))
    }
    .padding()
    .background(Color.black)
}
