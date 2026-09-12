//
//  LabFactsView.swift
//  DOSBTS
//
//  Chart Lab (DMNC-1500 / P5): the feature-sheet line and the cited-fact cards
//  under the lab chart.
//
//  Every number on screen here comes through `LabCaption`, which cannot print a
//  figure that has no sample size. The cards are ordinary tappable views — NOT
//  chart overlays — so they claim only their own frames and leave the chart's
//  scroll and scrub gestures alone (P0's errata).
//

import SwiftUI

// MARK: - LabFocusRequest

/// "Move the instrument to this fact." Carries a token so tapping the same card
/// twice re-focuses instead of being swallowed as an equal value.
struct LabFocusRequest: Equatable {
    let factID: String
    let date: Date
    let token: UUID

    init(fact: ChartFact) {
        self.factID = fact.id
        self.date = fact.anchor
        self.token = UUID()
    }
}

// MARK: - LabFactSheetLine

/// `24H · n=288 · MEDIAN 138 · P95 214 · 1 HYPO · 4 MEALS · 3 CLEAN`
struct LabFactSheetLine: View {
    let sheet: ChartFeatureSheet?
    let glucoseUnit: GlucoseUnit

    var body: some View {
        if let sheet {
            LabCaption(
                items: sheet.items(),
                glucoseUnit: glucoseUnit,
                font: DOSTypography.micro,
                color: AmberTheme.amberDark
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DOSSpacing.sm)
            .padding(.top, DOSSpacing.xxs)
            .accessibilityLabel("Feature sheet. \(LabCaption.text(for: sheet.items(), unit: glucoseUnit))")
        }
    }
}

// MARK: - LabFactCardList

struct LabFactCardList: View {
    // MARK: Internal

    let facts: [ChartFact]
    let glucoseUnit: GlucoseUnit
    let onSelect: (ChartFact) -> Void

    var body: some View {
        VStack(spacing: DOSSpacing.xs) {
            ForEach(Array(facts.enumerated()), id: \.element.id) { index, fact in
                LabFactCard(
                    index: index + 1,
                    fact: fact,
                    glucoseUnit: glucoseUnit,
                    onTap: { onSelect(fact) }
                )
                .stagedReveal(index, revealed: revealedStages)
            }
        }
        .padding(.horizontal, DOSSpacing.sm)
        .padding(.top, DOSSpacing.xs)
        .onAppear { cascade() }
        .onChange(of: facts.map(\.id)) { cascade() }
    }

    // MARK: Private

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealedStages = 0

    /// The digest's CRT boot cascade, async-stepped: same-tick writes to one
    /// `@State` coalesce into a single fade instead of staggering.
    private func cascade() {
        guard !reduceMotion else {
            revealedStages = facts.count
            return
        }
        revealedStages = 0
        Task { @MainActor in
            for stage in 0 ..< facts.count {
                withAnimation(AnimationTokens.easeReveal) {
                    revealedStages = stage + 1
                }
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }
}

// MARK: - LabFactCard

private struct LabFactCard: View {
    // MARK: Internal

    let index: Int
    let fact: ChartFact
    let glucoseUnit: GlucoseUnit
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: DOSSpacing.xs) {
                    Text("\(index)")
                        .font(DOSTypography.microLabel)
                        .foregroundStyle(AmberTheme.inkOnAmber)
                        .monospacedDigit()
                        .frame(width: 16, height: 16)
                        .background(accent)

                    LabCaption(
                        items: fact.title,
                        glucoseUnit: glucoseUnit,
                        font: DOSTypography.label,
                        color: titleColor
                    )
                }

                ForEach(Array(fact.lines.enumerated()), id: \.offset) { _, line in
                    LabCaption(items: line, glucoseUnit: glucoseUnit)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, DOSSpacing.xs)
            .padding(.horizontal, DOSSpacing.sm)
            .dosCard(.toast, stroke: accent, padding: nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken)
        .accessibilityHint("Moves the chart to this fact")
    }

    // MARK: Private

    private var accent: Color {
        fact.kind == .hypoOnset ? AmberTheme.cgaRed : AmberTheme.amber
    }

    private var titleColor: Color {
        fact.kind == .hypoOnset ? AmberTheme.cgaRed : AmberTheme.amberLight
    }

    private var spoken: String {
        ([LabCaption.text(for: fact.title, unit: glucoseUnit)]
            + fact.lines.map { LabCaption.text(for: $0, unit: glucoseUnit) })
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
    }
}
