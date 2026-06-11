//
//  GlucoseStatusBar.swift
//  DOSBTS
//
//  Persistent glucose + log actions on every tab (R7/R7b/R8), split across
//  two slim surfaces per user direction:
//  - GlucoseTopBar: a slim strip at the top of non-Overview tabs showing
//    the glucose value where the user is used to seeing it (hero position,
//    hero styling, much smaller).
//  - GlucoseStatusBar: the bottom log-action bar, mounted per tab via
//    safeAreaInset (KTD-3's fallback container — the Liquid Glass
//    accessory capsule showed glass edges around the DOS content).
//
//  Both read the same state the hero reads — `latestSensorGlucose`, the
//  shared GlucoseStaleness tiers, `treatmentCycleActive` — one source, no
//  copy, no separate refresh path (KTD-4).
//

import SwiftUI

// MARK: - Display model (unit-tested)

/// Pure mapping of store state → what the bar shows (the origin R7b state
/// table, verbatim). The views render this; tests pin every row.
struct GlucoseStatusBarModel: Equatable {
    enum Mode: Equatable {
        /// No sensor paired — "NO SENSOR", log actions still work.
        case noSensor
        /// Sensor paired, no reading yet — placeholder glyph + actions.
        case awaitingReading
        /// A reading: value (display units), optional trend arrow,
        /// staleness tier, and whether the treatment-cycle countdown
        /// indicator replaces the trend.
        case reading(valueText: String, trendText: String?, staleness: GlucoseStaleness, showsCountdown: Bool)
    }

    let mode: Mode
    /// R8: MEAL routes to the hypo-filtered sheet during a treatment cycle.
    let mealRoutesToHypoFiltered: Bool

    static func make(
        hasSensor: Bool,
        latestGlucose: SensorGlucose?,
        glucoseUnit: GlucoseUnit,
        treatmentCycleActive: Bool,
        now: Date = Date()
    ) -> GlucoseStatusBarModel {
        let mode: Mode
        if let glucose = latestGlucose {
            mode = .reading(
                valueText: glucose.glucoseValue.asGlucose(glucoseUnit: glucoseUnit),
                trendText: glucose.trend == .unknown ? nil : glucose.trend.description,
                staleness: GlucoseStaleness.of(readingTimestamp: glucose.timestamp, now: now),
                showsCountdown: treatmentCycleActive
            )
        } else if hasSensor {
            mode = .awaitingReading
        } else {
            mode = .noSensor
        }

        return GlucoseStatusBarModel(
            mode: mode,
            mealRoutesToHypoFiltered: treatmentCycleActive
        )
    }

    /// R8 routing: filtered entry during a cycle, normal sheet otherwise.
    var mealSheet: ActiveSheet {
        mealRoutesToHypoFiltered ? .filteredFoodEntry : .meal
    }
}

// MARK: - Bottom accessory: log actions

/// The bottom log-action bar, identical on every tab (R7, R8). Mounted
/// per tab via `safeAreaInset(edge: .bottom)` so it sits above the tab
/// bar with sharp DOS edges and never minimizes (R7b).
/// Reads only `model.mealSheet` — the richer mode/staleness fields of the
/// shared model are rendered by GlucoseTopBar.
struct GlucoseStatusBar: View {
    @EnvironmentObject var store: DirectStore
    @EnvironmentObject var sheets: SheetCoordinator

    private var model: GlucoseStatusBarModel {
        GlucoseStatusBarModel.make(
            hasSensor: store.state.sensor != nil,
            latestGlucose: store.state.latestSensorGlucose,
            glucoseUnit: store.state.glucoseUnit,
            treatmentCycleActive: store.state.treatmentCycleActive
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(AmberTheme.dosBorder)

            HStack(spacing: DOSSpacing.sm) {
                if DirectConfig.showInsulinInput, store.state.showInsulinInput {
                    barAction(title: "INSULIN", action: { sheets.present(.insulin) }) {
                        Image(systemName: "syringe")
                            .font(DOSTypography.body)
                    }
                }

                // model is read inside the closure so the R8 routing decision
                // uses the treatment-cycle state at TAP time, not render time.
                barAction(title: "MEAL", action: { sheets.present(model.mealSheet) }) {
                    AppleIcon().frame(width: 16, height: 16)
                }
            }
            .padding(.horizontal, DOSSpacing.md)
            .padding(.vertical, DOSSpacing.xs)
            .background(AmberTheme.dosBlack)
        }
    }

    /// The Overview quick-action look: ghost box, icon beside caption,
    /// 44pt target.
    private func barAction(
        title: String,
        action: @escaping () -> Void,
        @ViewBuilder icon: @escaping () -> some View
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DOSSpacing.xs) {
                icon()
                    .frame(height: 16)
                Text(title)
                    .font(DOSTypography.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(DOSButtonStyle(variant: .ghost))
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Top bar: slim glucose strip

/// Slim glucose strip pinned above the content of non-Overview tabs — the
/// value sits at the top where the hero puts it, in hero styling (glucose
/// gradient color, monospace, phosphor glow), just much smaller (R7b).
struct GlucoseTopBar: View {
    @EnvironmentObject var store: DirectStore

    private func model(now: Date) -> GlucoseStatusBarModel {
        GlucoseStatusBarModel.make(
            hasSensor: store.state.sensor != nil,
            latestGlucose: store.state.latestSensorGlucose,
            glucoseUnit: store.state.glucoseUnit,
            treatmentCycleActive: store.state.treatmentCycleActive,
            now: now
        )
    }

    var body: some View {
        // TimelineView drives the minute tick for staleness re-evaluation —
        // unlike a stored Timer publisher, it isn't recreated (and restarted)
        // every time the view struct re-inits on a store update, so the tick
        // cadence survives render churn and nothing leaks across the three
        // tabs that host this strip.
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            bar(model: model(now: timeline.date))
        }
    }

    @ViewBuilder
    private func bar(model: GlucoseStatusBarModel) -> some View {
        HStack(spacing: DOSSpacing.xs) {
            switch model.mode {
            case .noSensor:
                Text("NO SENSOR")
                    .font(DOSTypography.mono(size: 12, weight: .semibold))
                    .foregroundStyle(AmberTheme.amber)

            case .awaitingReading:
                Text("---")
                    .font(DOSTypography.mono(size: 14, weight: .bold))
                    .foregroundStyle(AmberTheme.amberDark)

            case .reading(let valueText, let trendText, let staleness, let showsCountdown):
                // The value never truncates (R7 content priority).
                Text(verbatim: valueText)
                    .font(DOSTypography.mono(size: 15, weight: .bold))
                    .foregroundStyle(valueColor)
                    .dosGlowLarge(color: valueColor)
                    .fixedSize()

                if showsCountdown {
                    // R7b: countdown indicator replaces the trend during a
                    // treatment cycle; the full countdown lives in the
                    // Overview banner the safety flows route to.
                    Image(systemName: "timer")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AmberTheme.cgaGreen)
                } else if let trendText {
                    // Trend drops first when space runs out.
                    Text(verbatim: trendText)
                        .font(DOSTypography.mono(size: 13, weight: .bold))
                        .foregroundStyle(valueColor)
                        .layoutPriority(-1)
                }

                if let staleLabel = staleness.minutesAgoLabel {
                    HStack(spacing: 2) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                        Text(verbatim: staleLabel)
                            .font(DOSTypography.tabBar)
                    }
                    .foregroundStyle(AmberTheme.stalenessColor(staleness))
                    .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(AmberTheme.dosBlack)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AmberTheme.amberDark.opacity(0.3))
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: accessibilityDescription(for: model)))
    }

    /// VoiceOver reads a sentence, not raw arrow glyphs.
    private func accessibilityDescription(for model: GlucoseStatusBarModel) -> String {
        switch model.mode {
        case .noSensor:
            return LocalizedString("No sensor paired")
        case .awaitingReading:
            return LocalizedString("Waiting for glucose reading")
        case .reading(let valueText, _, let staleness, let showsCountdown):
            var parts = ["\(LocalizedString("Glucose")) \(valueText) \(store.state.glucoseUnit.localizedDescription)"]
            if showsCountdown {
                parts.append(LocalizedString("treatment recheck countdown running"))
            } else if let trend = store.state.latestSensorGlucose?.trend, trend != .unknown {
                parts.append("\(LocalizedString("trend")) \(trend.description)")
            }
            if let staleLabel = staleness.minutesAgoLabel {
                parts.append(staleLabel)
            }
            return parts.joined(separator: ", ")
        }
    }

    /// Mirrors the hero/alarm color state (R7b "alarm firing" row): the
    /// same gradient the hero uses, red below low / above high.
    private var valueColor: Color {
        guard let glucose = store.state.latestSensorGlucose else { return AmberTheme.amber }
        return AmberTheme.glucoseColor(
            forValue: glucose.glucoseValue,
            low: store.state.alarmLow,
            high: store.state.alarmHigh
        )
    }
}
