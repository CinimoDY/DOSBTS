//
//  GlucoseActivityWidget.swift
//  DOSBTSWidget
//

import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - GlucoseActivityWidget

struct GlucoseActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SensorGlucoseActivityAttributes.self) { context in
            GlucoseActivityView(context: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    DynamicIslandCenterView(context: context.state)
                }
            } compactLeading: {
                if let latestGlucose = context.state.glucose,
                   let glucoseUnit = context.state.glucoseUnit,
                   let connectionState = context.state.connectionState
                {
                    Text(latestGlucose.glucoseValue.asGlucose(glucoseUnit: glucoseUnit))
                        .font(WidgetFonts.mono(size: 16, weight: .bold))
                        .foregroundStyle(AmberTheme.amber)
                        .strikethrough(connectionState != .connected, color: AmberTheme.cgaRed)
                        .padding(.leading, 7.5)
                }
            } compactTrailing: {
                if let latestGlucose = context.state.glucose {
                    HStack(spacing: 4) {
                        Text(latestGlucose.trend.description)
                            .font(WidgetFonts.mono(size: 14, weight: .bold))
                            .foregroundStyle(AmberTheme.amber)

                        if let iob = context.state.iob {
                            Text(String(format: "%.1f", iob))
                                .font(WidgetFonts.mono(size: 11, weight: .regular))
                                .foregroundStyle(AmberTheme.cgaCyan)
                        }
                    }
                    .padding(.trailing, 7.5)
                }
            } minimal: {
                if let latestGlucose = context.state.glucose,
                   let glucoseUnit = context.state.glucoseUnit,
                   let connectionState = context.state.connectionState
                {
                    Text(latestGlucose.glucoseValue.asGlucose(glucoseUnit: glucoseUnit))
                        .font(WidgetFonts.mono(size: 17, weight: .bold))
                        .foregroundStyle(AmberTheme.amber)
                        .strikethrough(connectionState != .connected, color: AmberTheme.cgaRed)
                }
            }
        }
    }
}

// MARK: - GlucoseStatusContext

protocol GlucoseStatusContext {
    var context: SensorGlucoseActivityAttributes.GlucoseStatus { get }
}

extension GlucoseStatusContext {
    var warning: String? {
        if let sensorState = context.sensorState, sensorState != .ready {
            return sensorState.localizedDescription
        }

        if let connectionState = context.connectionState, connectionState != .connected {
            return connectionState.localizedDescription
        }

        return nil
    }

    /// Resolves the active-profile thresholds via the shared helper in
    /// `Library/Content/AlarmProfile.swift`. All-or-nothing fallback: if any
    /// of the 8 ContentState profile fields is nil, returns the legacy
    /// `alarmLow`/`alarmHigh` (a stable day-anchored fallback for pre-upgrade
    /// in-flight activities). Mixing a per-profile field with a legacy field
    /// would yield a threshold pair that exists in neither profile.
    func effectiveAlarmThresholds(at date: Date) -> (low: Int, high: Int, profile: AlarmProfile) {
        let resolved = resolveActiveProfileThresholds(at: date) { key in
            switch key {
            case AppGroupAlarmProfileKeys.dayAlarmHigh: return context.dayAlarmHigh
            case AppGroupAlarmProfileKeys.dayAlarmLow: return context.dayAlarmLow
            case AppGroupAlarmProfileKeys.nightAlarmHigh: return context.nightAlarmHigh
            case AppGroupAlarmProfileKeys.nightAlarmLow: return context.nightAlarmLow
            case AppGroupAlarmProfileKeys.nightStartHour: return context.nightStartHour
            case AppGroupAlarmProfileKeys.nightStartMinute: return context.nightStartMinute
            case AppGroupAlarmProfileKeys.nightEndHour: return context.nightEndHour
            case AppGroupAlarmProfileKeys.nightEndMinute: return context.nightEndMinute
            default: return nil
            }
        }
        if let resolved {
            return (resolved.alarmLow, resolved.alarmHigh, resolved.profile)
        }
        return (context.alarmLow, context.alarmHigh, .day)
    }

    /// True only when the active profile is night AND the new per-profile data
    /// is present (so we don't show a moon glyph on legacy-fallback activities
    /// whose schedule data we don't have).
    var nightProfileActive: Bool {
        let resolved = effectiveAlarmThresholds(at: Date())
        return resolved.profile == .night && context.nightStartHour != nil
    }

    func isAlarm(glucose: any Glucose) -> Bool {
        let resolved = effectiveAlarmThresholds(at: Date())
        return glucose.glucoseValue < resolved.low || glucose.glucoseValue > resolved.high
    }

    func getGlucoseColor(glucose: any Glucose) -> Color {
        isAlarm(glucose: glucose) ? AmberTheme.cgaRed : AmberTheme.amber
    }
}

// MARK: - DynamicIslandCenterView

struct DynamicIslandCenterView: View, GlucoseStatusContext {
    @State var context: SensorGlucoseActivityAttributes.GlucoseStatus

    var body: some View {
        VStack(spacing: 4) {
            if let latestGlucose = context.glucose, let glucoseUnit = context.glucoseUnit {
                HStack(alignment: .lastTextBaseline, spacing: 16) {
                    if latestGlucose.type != .high {
                        Text(verbatim: latestGlucose.glucoseValue.asGlucose(glucoseUnit: glucoseUnit))
                            .font(WidgetFonts.mono(size: 52, weight: .bold))
                            .foregroundStyle(getGlucoseColor(glucose: latestGlucose))
                            .phosphorGlow(color: getGlucoseColor(glucose: latestGlucose))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: latestGlucose.trend.description)
                                .font(WidgetFonts.mono(size: 28, weight: .regular))
                                .foregroundStyle(getGlucoseColor(glucose: latestGlucose))

                            if let minuteChange = latestGlucose.minuteChange?.asMinuteChange(glucoseUnit: glucoseUnit) {
                                Text(verbatim: minuteChange)
                                    .font(WidgetFonts.caption)
                                    .foregroundStyle(AmberTheme.amber)
                            }
                        }
                    } else {
                        Text("HIGH")
                            .font(WidgetFonts.mono(size: 52, weight: .bold))
                            .foregroundStyle(AmberTheme.cgaRed)
                            .phosphorGlow(color: AmberTheme.cgaRed)
                    }
                }

                if let warning = warning {
                    Text(verbatim: warning)
                        .font(WidgetFonts.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(AmberTheme.cgaRed)
                        .foregroundStyle(AmberTheme.amberLight)
                } else {
                    HStack(spacing: 16) {
                        if let iob = context.iob {
                            Text(String(format: "IOB %.1fU", iob))
                                .foregroundStyle(AmberTheme.cgaCyan)
                        }
                        Text(latestGlucose.timestamp, style: .time)
                            .foregroundStyle(AmberTheme.amberDark)
                    }
                    .font(WidgetFonts.caption)
                }
            } else {
                Text("No Data")
                    .font(WidgetFonts.mono(size: 28, weight: .bold))
                    .foregroundStyle(AmberTheme.cgaRed)

                Text(Date(), style: .time)
                    .font(WidgetFonts.caption)
                    .foregroundStyle(AmberTheme.amberDark)
            }
        }
        .padding(.bottom)
        .widgetBackground(backgroundView: AmberTheme.dosBlack)
    }
}

// MARK: - GlucoseActivityView

struct GlucoseActivityView: View, GlucoseStatusContext {
    @State var context: SensorGlucoseActivityAttributes.GlucoseStatus

    var body: some View {
        HStack(spacing: 12) {
            if let latestGlucose = context.glucose, let glucoseUnit = context.glucoseUnit {
                // Left: Glucose + trend
                VStack(spacing: 2) {
                    HStack(alignment: .top, spacing: 6) {
                        Group {
                            if latestGlucose.type != .high {
                                Text(verbatim: latestGlucose.glucoseValue.asGlucose(glucoseUnit: glucoseUnit))
                            } else {
                                Text("HIGH")
                            }
                        }
                        .bold()
                        .foregroundStyle(getGlucoseColor(glucose: latestGlucose))
                        .font(WidgetFonts.mono(size: 36, weight: .bold))
                        .phosphorGlow(color: getGlucoseColor(glucose: latestGlucose))

                        Text(verbatim: latestGlucose.trend.description)
                            .foregroundStyle(getGlucoseColor(glucose: latestGlucose))
                            .font(WidgetFonts.mono(size: 26, weight: .regular))
                    }

                    if let warning = warning {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(AmberTheme.cgaRed)
                            Text(verbatim: warning)
                                .bold()
                        }
                        .font(WidgetFonts.caption)
                    } else if let minuteChange = latestGlucose.minuteChange?.asMinuteChange(glucoseUnit: glucoseUnit) {
                        Text(verbatim: minuteChange)
                            .font(WidgetFonts.caption)
                            .foregroundStyle(AmberTheme.amber)
                    }
                }

                // Center: Mini sparkline (3h)
                if let sparkline = context.sparkline, sparkline.count >= 2 {
                    // Take last ~6 points for 3h view
                    let recentPoints = sparkline.count > 6 ? Array(sparkline.suffix(6)) : sparkline
                    GeometryReader { geo in
                        let result = SparklineBuilder.build(
                            values: recentPoints,
                            in: CGRect(x: 0, y: 0, width: geo.size.width, height: geo.size.height)
                        )
                        result.path
                            .stroke(AmberTheme.amber, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                            .shadow(color: AmberTheme.amber.opacity(0.3), radius: 2)
                    }
                    .frame(width: 60, height: 36)
                }

                Spacer(minLength: 0)

                // Right: IOB + timestamp
                VStack(alignment: .trailing, spacing: 4) {
                    if let iob = context.iob {
                        Text(String(format: "%.1fU", iob))
                            .font(WidgetFonts.label)
                            .foregroundStyle(AmberTheme.cgaCyan)
                    }

                    Text(latestGlucose.timestamp, style: .time)
                        .font(WidgetFonts.caption)
                        .monospacedDigit()
                        .foregroundStyle(AmberTheme.amberDark)

                    if let stopDate = context.stopDate {
                        Text(stopDate, style: .relative)
                            .font(WidgetFonts.tabBar)
                            .monospacedDigit()
                            .foregroundStyle(AmberTheme.amber)
                            .lineLimit(1)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Text("No Data")
                        .bold()
                        .font(WidgetFonts.mono(size: 32, weight: .bold))
                        .foregroundStyle(AmberTheme.cgaRed)

                    Text(Date(), style: .time)
                        .font(WidgetFonts.caption)
                        .foregroundStyle(AmberTheme.amberDark)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .widgetBackground(backgroundView: AmberTheme.dosBlack)
        .overlay(alignment: .topTrailing) {
            if nightProfileActive {
                Image(systemName: "moon.fill")
                    .font(WidgetFonts.mono(size: 10))
                    .foregroundStyle(AmberTheme.amberDark)
                    .padding(6)
                    .accessibilityLabel("Night profile active")
            }
        }
    }
}

// MARK: - GlucoseActivityWidget_Previews

struct GlucoseActivityWidget_Previews: PreviewProvider {
    static var previews: some View {
        GlucoseActivityView(
            context: SensorGlucoseActivityAttributes.GlucoseStatus(
                alarmLow: 80,
                alarmHigh: 160,
                sensorState: .expired,
                connectionState: .disconnected,
                glucoseUnit: .mgdL,
                startDate: Date(),
                restartDate: Date(),
                stopDate: Date()
            )
        ).previewContext(WidgetPreviewContext(family: .systemMedium))

        GlucoseActivityView(
            context: SensorGlucoseActivityAttributes.GlucoseStatus(
                alarmLow: 80,
                alarmHigh: 160,
                sensorState: .ready,
                connectionState: .connected,
                glucose: SensorGlucose(glucoseValue: 120, minuteChange: 2),
                glucoseUnit: .mgdL,
                iob: 2.3,
                sparkline: [95, 100, 110, 125, 118, 120],
                startDate: Date(),
                restartDate: Date(),
                stopDate: Date()
            )
        ).previewContext(WidgetPreviewContext(family: .systemMedium))
    }
}
