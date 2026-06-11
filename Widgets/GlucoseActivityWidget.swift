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
                        .foregroundColor(WidgetColors.amber)
                        .strikethrough(connectionState != .connected, color: WidgetColors.cgaRed)
                        .padding(.leading, 7.5)
                }
            } compactTrailing: {
                if let latestGlucose = context.state.glucose {
                    HStack(spacing: 4) {
                        Text(latestGlucose.trend.description)
                            .font(WidgetFonts.mono(size: 14, weight: .bold))
                            .foregroundColor(WidgetColors.amber)

                        if let iob = context.state.iob {
                            Text(String(format: "%.1f", iob))
                                .font(WidgetFonts.mono(size: 11, weight: .regular))
                                .foregroundColor(WidgetColors.cgaCyan)
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
                        .font(.body)
                        .bold()
                        .foregroundColor(WidgetColors.amber)
                        .strikethrough(connectionState != .connected, color: WidgetColors.cgaRed)
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
        isAlarm(glucose: glucose) ? WidgetColors.cgaRed : WidgetColors.amber
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
                            .foregroundColor(getGlucoseColor(glucose: latestGlucose))
                            .phosphorGlow(color: getGlucoseColor(glucose: latestGlucose))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: latestGlucose.trend.description)
                                .font(WidgetFonts.mono(size: 28, weight: .regular))
                                .foregroundColor(getGlucoseColor(glucose: latestGlucose))

                            if let minuteChange = latestGlucose.minuteChange?.asMinuteChange(glucoseUnit: glucoseUnit) {
                                Text(verbatim: minuteChange)
                                    .font(WidgetFonts.caption)
                                    .foregroundColor(WidgetColors.amber)
                            }
                        }
                    } else {
                        Text("HIGH")
                            .font(WidgetFonts.mono(size: 52, weight: .bold))
                            .foregroundColor(WidgetColors.cgaRed)
                            .phosphorGlow(color: WidgetColors.cgaRed)
                    }
                }

                if let warning = warning {
                    Text(verbatim: warning)
                        .font(WidgetFonts.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(WidgetColors.cgaRed)
                        .foregroundColor(WidgetColors.amberLight)
                } else {
                    HStack(spacing: 16) {
                        if let iob = context.iob {
                            Text(String(format: "IOB %.1fU", iob))
                                .foregroundColor(WidgetColors.cgaCyan)
                        }
                        Text(latestGlucose.timestamp, style: .time)
                            .foregroundColor(WidgetColors.amberDark)
                    }
                    .font(WidgetFonts.caption)
                }
            } else {
                Text("No Data")
                    .font(WidgetFonts.mono(size: 28, weight: .bold))
                    .foregroundColor(WidgetColors.cgaRed)

                Text(Date(), style: .time)
                    .font(WidgetFonts.caption)
                    .foregroundColor(WidgetColors.amberDark)
            }
        }
        .padding(.bottom)
        .widgetBackground(backgroundView: WidgetColors.dosBlack)
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
                        .foregroundColor(getGlucoseColor(glucose: latestGlucose))
                        .font(WidgetFonts.mono(size: 36, weight: .bold))
                        .phosphorGlow(color: getGlucoseColor(glucose: latestGlucose))

                        Text(verbatim: latestGlucose.trend.description)
                            .foregroundColor(getGlucoseColor(glucose: latestGlucose))
                            .font(WidgetFonts.mono(size: 26, weight: .regular))
                    }

                    if let warning = warning {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(WidgetColors.cgaRed)
                            Text(verbatim: warning)
                                .bold()
                        }
                        .font(WidgetFonts.caption)
                    } else if let minuteChange = latestGlucose.minuteChange?.asMinuteChange(glucoseUnit: glucoseUnit) {
                        Text(verbatim: minuteChange)
                            .font(WidgetFonts.caption)
                            .foregroundColor(WidgetColors.amber)
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
                            .stroke(WidgetColors.amber, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                            .shadow(color: WidgetColors.amber.opacity(0.3), radius: 2)
                    }
                    .frame(width: 60, height: 36)
                }

                Spacer(minLength: 0)

                // Right: IOB + timestamp
                VStack(alignment: .trailing, spacing: 4) {
                    if let iob = context.iob {
                        Text(String(format: "%.1fU", iob))
                            .font(WidgetFonts.label)
                            .foregroundColor(WidgetColors.cgaCyan)
                    }

                    Text(latestGlucose.timestamp, style: .time)
                        .font(WidgetFonts.caption)
                        .monospacedDigit()
                        .foregroundColor(WidgetColors.amberDark)

                    if let stopDate = context.stopDate {
                        Text(stopDate, style: .relative)
                            .font(WidgetFonts.tabBar)
                            .monospacedDigit()
                            .foregroundColor(WidgetColors.amber)
                            .lineLimit(1)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Text("No Data")
                        .bold()
                        .font(WidgetFonts.mono(size: 32, weight: .bold))
                        .foregroundColor(WidgetColors.cgaRed)

                    Text(Date(), style: .time)
                        .font(WidgetFonts.caption)
                        .foregroundColor(WidgetColors.amberDark)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .widgetBackground(backgroundView: WidgetColors.dosBlack)
        .overlay(alignment: .topTrailing) {
            if nightProfileActive {
                Image(systemName: "moon.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(WidgetColors.amberDark)
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
