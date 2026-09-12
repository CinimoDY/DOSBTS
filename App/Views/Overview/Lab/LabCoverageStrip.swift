//
//  LabCoverageStrip.swift
//  DOSBTS
//
//  Chart Lab P1 (DMNC-1506) — the POST strip.
//
//  The lab's honesty surface: for every stream the night could have drawn, it
//  says whether the data is there, absent, never asked for, or broken. A chart
//  that silently omits a stream teaches the wrong lesson about your own night;
//  this row is what stops that.
//
//  All of the decisions live in `LabCoverage` (pure). This file only paints.
//

import SwiftUI

struct LabCoverageStrip: View {
    @EnvironmentObject var store: DirectStore

    let snapshot: LabWindowSnapshot

    var body: some View {
        HStack(spacing: DOSSpacing.xs) {
            ForEach(LabCoverage.cells(snapshot: snapshot, sensorIntervalMinutes: store.state.sensorInterval)) { cell in
                cellView(cell)
            }
        }
        .font(DOSTypography.microLabel)
        .frame(maxWidth: .infinity)
        .padding(.top, DOSSpacing.xs)
        .padding(.horizontal, DOSSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stream coverage")
    }

    @ViewBuilder
    private func cellView(_ cell: LabCoverageCell) -> some View {
        switch cell.tone {
        case .unavailable:
            // The one actionable state: we have never been allowed to ask.
            Button {
                store.dispatch(.setSettingsCategory(category: .integrations))
            } label: {
                Text(cell.text)
                    .foregroundStyle(AmberTheme.amberLight)
                    .underline()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(cell.label) unavailable, open Apple Health settings")

        case .loaded:
            Text(cell.text).foregroundStyle(AmberTheme.amber)

        case .empty:
            Text(cell.text).foregroundStyle(AmberTheme.amberDark)

        case .failed:
            Text(cell.text).foregroundStyle(AmberTheme.cgaRed)
        }
    }
}

// MARK: - LabSleepLane

/// The sleep-stage lane: one cell per sample, taller the deeper the sleep,
/// sitting under the plot on the same time axis.
///
/// Deliberately a plain `GeometryReader` strip and not a second `Chart` — a
/// second chart would bring its own insets and its own axis, and the two could
/// drift apart by a pixel or two at the edges.
struct LabSleepLane: View {
    let samples: [SleepSample]
    let interval: DateInterval
    /// Matches `LabChartView`'s plot inset so the lane lines up with the trace.
    var sideInset: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let usable = max(1, geo.size.width - 2 * sideInset)

            ZStack(alignment: .bottomLeading) {
                ForEach(drawable) { sample in
                    let start = fraction(of: sample.start) * usable + sideInset
                    let end = fraction(of: sample.end) * usable + sideInset

                    Rectangle()
                        .fill(AmberTheme.cgaCyan.opacity(sample.stage.laneWeight))
                        .frame(width: max(1, end - start), height: Self.height * sample.stage.laneWeight)
                        .offset(x: start)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(height: Self.height)
        .overlay(alignment: .topTrailing) {
            Text("SLEEP")
                .font(DOSTypography.micro)
                .foregroundStyle(AmberTheme.cgaCyan)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: Private

    private static let height: CGFloat = 18

    /// `inBed` spans are the envelope, not a stage — drawing them would paint a
    /// solid bar under every real stage cell.
    private var drawable: [SleepSample] {
        samples.filter { $0.stage != .inBed && $0.end > $0.start }
    }

    private func fraction(of date: Date) -> CGFloat {
        let span = interval.duration
        guard span > 0 else { return 0 }
        let offset = date.timeIntervalSince(interval.start) / span
        return CGFloat(min(1, max(0, offset)))
    }

    private var accessibilityText: String {
        let asleep = samples.filter { $0.stage.isAsleep }.count
        return "Sleep stages, \(asleep) asleep spans"
    }
}
