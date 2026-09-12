//
//  LabNightView.swift
//  DOSBTS
//
//  LAB: NIGHT (DMNC-1506) — 20:00 the evening before through 10:00, the one
//  period no shipping window can show whole.
//
//  Sleep stages, heart rate, the evening dose's IOB tail and the last meal's
//  response ribbon all sit under the same trace, over one interval fetched by
//  one loader; the header names the night's numbers WITH their sample sizes;
//  the POST strip says which streams are actually behind what you are looking
//  at. Nothing here is dosing advice.
//

import SwiftUI

struct LabNightView: View {
    // MARK: Internal

    @EnvironmentObject var store: DirectStore

    var body: some View {
        VStack(spacing: 0) {
            header

            content

            LabFooter()
                .padding(.bottom, DOSSpacing.xxs)
        }
        .onAppear { load() }
    }

    // MARK: Private

    @State private var followStatus: LabFollowStatus = .following

    /// The window the tab is asking for. Derived from the pager's selected day
    /// so `<` / `>` move the night; the DRAWN window is always the snapshot's
    /// own interval, so nothing flickers into a half-loaded state.
    private var requestedInterval: DateInterval {
        NightWindow.interval(for: store.state.selectedDate ?? Date())
    }

    private var snapshot: LabWindowSnapshot? {
        store.state.labWindow
    }

    private var summary: NightSummary {
        guard let snapshot else { return .empty }
        return NightSummary.make(
            sleep: snapshot.sleep,
            readings: snapshot.readings,
            unit: store.state.glucoseUnit
        )
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(sleepLine)
                .foregroundStyle(AmberTheme.cgaCyan)

            Text(glucoseLine)
                .foregroundStyle(AmberTheme.amberLight)
        }
        .font(DOSTypography.caption)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DOSSpacing.sm)
    }

    /// `IN BED 23:10 · ASLEEP 6H40 · AWAKE ×2`, or an honest absence.
    private var sleepLine: String {
        guard let inBed = summary.inBed, summary.asleepMinutes > 0 else {
            return "SLEEP —"
        }
        let hours = summary.asleepMinutes / 60
        let minutes = summary.asleepMinutes % 60
        return "IN BED \(inBed.toLocalTime()) · ASLEEP \(hours)H\(String(format: "%02d", minutes)) · AWAKE ×\(summary.awakeCount)"
    }

    /// `ASLEEP 112 → WAKE 152 · ↑ +40 · n=81`. Every number with its `n`.
    private var glucoseLine: String {
        guard let atSleep = summary.glucoseAtSleep,
              let atWake = summary.glucoseAtWake,
              let rise = summary.riseByWake
        else {
            return "NIGHT GLUCOSE — · n=\(snapshot?.readingsInWindow.count ?? 0)"
        }

        let arrow = rise.value > 0 ? "↑" : (rise.value < 0 ? "↓" : "→")
        let sign = rise.value > 0 ? "+" : ""
        return "ASLEEP \(format(atSleep.value)) → WAKE \(format(atWake.value)) · \(arrow) \(sign)\(format(rise.value)) · n=\(rise.n)"
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let snapshot {
            // One branch, readings or not: `LabChartView` renders its own empty
            // state for a window it found nothing in, and keeps the day pager
            // mounted — which is the only way back off an empty night.
            loadedWindow(snapshot)
        } else {
            VStack {
                Spacer()
                FiguresLoadingView.inline
                Spacer()
            }
            // Greedy: the chart it stands in for is, so the footer does not
            // ride up to the header while the window loads.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func loadedWindow(_ snapshot: LabWindowSnapshot) -> some View {
        LabChartView(
            overlays: ReportType.labNight.labOverlays,
            followStatus: $followStatus,
            windowInputs: LabChartInputs(
                window: snapshot,
                state: store.state,
                overlays: ReportType.labNight.labOverlays
            )
        )

        LabSleepLane(samples: snapshot.sleep, interval: snapshot.interval)
            .padding(.horizontal, DOSSpacing.sm)

        LabCoverageStrip(snapshot: snapshot)

        modeRow

        LabLegendRow(items: [
            LabLegendItem(glyph: "▮", label: "2H RESPONSE", color: AmberTheme.amber),
            LabLegendItem(glyph: "▒", label: "AWAKE", color: AmberTheme.cgaCyan),
            LabLegendItem(glyph: "╌╌", label: "HR", color: AmberTheme.cgaMagenta),
            LabLegendItem(glyph: "POST", label: "COVERAGE PER STREAM", color: AmberTheme.amberLight),
        ])
    }

    /// `NIGHT · DAY · WK`. V1 ships NIGHT; the other two are dimmed rather than
    /// hidden, so the shape of what is coming is visible (CLAUDE.md: dependent
    /// controls dim, they do not disappear).
    private var modeRow: some View {
        HStack(spacing: DOSSpacing.md) {
            ForEach(NightMode.allCases, id: \.self) { mode in
                VStack(spacing: DOSSpacing.xxs) {
                    Text(mode.label)
                        .font(DOSTypography.mono(size: 15, weight: mode == .night ? .bold : .regular))
                        .foregroundStyle(mode == .night ? AmberTheme.amber : AmberTheme.amberDark)
                    Rectangle()
                        .fill(AmberTheme.amber)
                        .frame(height: 2)
                        .opacity(mode == .night ? 1 : 0)
                }
                .fixedSize()
                .opacity(mode == .night ? 1 : 0.5)
                .disabled(mode != .night)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DOSSpacing.xs)
        .accessibilityHidden(true)
    }

    private func format(_ value: Double) -> String {
        let formatter = store.state.glucoseUnit == .mmolL
            ? GlucoseFormatters.mmolLFormatter
            : GlucoseFormatters.mgdLFormatter
        return formatter.string(from: value as NSNumber) ?? "—"
    }

    /// On-demand, like the Ratio Lab's evidence load: no app-activation path
    /// pays for a window nobody is looking at. Re-entry keeps the previous
    /// window on screen until the fresh one lands, so there is no flash of empty.
    private func load() {
        store.dispatch(.loadLabWindow(interval: requestedInterval, streams: LabNightStreams.all))
    }
}

// MARK: - NightMode

private enum NightMode: CaseIterable {
    case night
    case day
    case week

    var label: String {
        switch self {
        case .night: return "NIGHT"
        case .day: return "DAY"
        case .week: return "WK"
        }
    }
}
