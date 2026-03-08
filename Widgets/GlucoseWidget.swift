//
//  GlucoseWidget.swift
//  App
//

import SwiftUI
import WidgetKit

private let placeholderLowGlucose = SensorGlucose(timestamp: Date(), rawGlucoseValue: 70, intGlucoseValue: 80, minuteChange: 2)
private let placeholderGlucose = SensorGlucose(timestamp: Date(), rawGlucoseValue: 100, intGlucoseValue: 110, minuteChange: 5)
private let placeholderHighGlucose = SensorGlucose(timestamp: Date(), rawGlucoseValue: 400, intGlucoseValue: 410, minuteChange: 5)
private let placeholderGlucoseUnit = GlucoseUnit.mgdL

// MARK: - GlucoseEntry

struct GlucoseEntry: TimelineEntry {
    // MARK: Lifecycle

    init() {
        self.date = Date()
        self.glucose = nil
        self.glucoseUnit = nil
    }

    init(date: Date) {
        self.date = date
        self.glucose = nil
        self.glucoseUnit = nil
    }

    init(date: Date, glucose: SensorGlucose, glucoseUnit: GlucoseUnit) {
        self.date = date
        self.glucose = glucose
        self.glucoseUnit = glucoseUnit
    }

    // MARK: Internal

    let date: Date
    let glucose: SensorGlucose?
    let glucoseUnit: GlucoseUnit?
}

// MARK: - GlucoseUpdateProvider

struct GlucoseUpdateProvider: TimelineProvider {
    func placeholder(in context: Context) -> GlucoseEntry {
        return GlucoseEntry(date: Date(), glucose: placeholderGlucose, glucoseUnit: placeholderGlucoseUnit)
    }

    func getSnapshot(in context: Context, completion: @escaping (GlucoseEntry) -> ()) {
        let entry = GlucoseEntry()

        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let entries = [
            GlucoseEntry(),
        ]

        let reloadDate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!

        let timeline = Timeline(entries: entries, policy: .after(reloadDate))
        completion(timeline)
    }
}

// MARK: - GlucoseView

struct GlucoseView: View {
    @Environment(\.widgetFamily) var size

    var entry: GlucoseEntry

    var glucoseUnit: GlucoseUnit? {
        entry.glucoseUnit ?? UserDefaults.shared.glucoseUnit
    }

    var glucose: SensorGlucose? {
        entry.glucose ?? UserDefaults.shared.latestSensorGlucose
    }

    var body: some View {
        if let glucose,
           let glucoseUnit
        {
            switch size {
            case .accessoryRectangular:
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text(glucose.glucoseValue.asGlucose(glucoseUnit: glucoseUnit))
                        .widgetAccentable()
                        .bold()
                        .font(DOSTypography.mono(size: 35, weight: .bold))

                    VStack(alignment: .leading) {
                        Text(glucose.trend.description)
                            .font(DOSTypography.bodySmall)
                            .bold()

                        Text(glucose.timestamp.toLocalTime())
                            .font(DOSTypography.tabBar)
                    }
                }
                .widgetBackground(backgroundView: Color("WidgetBackground"))

            case .accessoryCircular:
                VStack(alignment: .center) {
                    Text(glucose.glucoseValue.asGlucose(glucoseUnit: glucoseUnit))
                        .widgetAccentable()
                        .font(DOSTypography.mono(size: 25, weight: .bold))
                        .bold()

                    Text(glucose.timestamp.toLocalTime())
                        .font(DOSTypography.tabBar)
                }
                .widgetBackground(backgroundView: Color("WidgetBackground"))

            case .systemSmall:
                ZStack {
                    LinearGradient(gradient: Gradient(colors: [Color.black, AmberTheme.amberMuted]), startPoint: .top, endPoint: .bottom)

                    VStack(spacing: 10) {
                        if let appIcon = UIImage(named: "AppIcon") {
                            Image(uiImage: appIcon)
                                .cornerRadius(4)
                        }

                        HStack(alignment: .lastTextBaseline, spacing: 10) {
                            if glucose.type != .high {
                                Text(verbatim: glucose.glucoseValue.asGlucose(glucoseUnit: glucoseUnit))
                                    .font(DOSTypography.mono(size: 42, weight: .regular))

                                VStack(alignment: .leading) {
                                    Text(verbatim: glucose.trend.description)
                                        .font(DOSTypography.mono(size: 18, weight: .regular))

                                    if let minuteChange = glucose.minuteChange?.asShortMinuteChange(glucoseUnit: glucoseUnit) {
                                        Text(verbatim: minuteChange)
                                            .font(DOSTypography.caption)
                                    } else {
                                        Text(verbatim: "?")
                                            .font(DOSTypography.caption)
                                    }
                                }
                            } else {
                                Text("HIGH")
                                    .font(DOSTypography.mono(size: 64, weight: .bold))
                                    .foregroundColor(AmberTheme.cgaRed)
                            }
                        }

                        VStack {
                            Text("Updated")
                                .textCase(.uppercase)
                                .font(DOSTypography.caption)
                            Text(glucose.timestamp, style: .time)
                                .monospacedDigit()
                        }
                        .opacity(0.5)
                        .font(DOSTypography.caption)
                    }
                }
                .widgetBackground(backgroundView: Color("WidgetBackground"))

            default:
                Text("")
            }
        }
    }
}

// MARK: - GlucoseWidget

struct GlucoseWidget: Widget {
    let kind: String = "GlucoseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GlucoseUpdateProvider()) { entry in
            GlucoseView(entry: entry)
        }
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .systemSmall])
        .configurationDisplayName("Glucose widget")
        .description("Glucose widget description")
    }
}

// MARK: - GlucoseWidget_Previews

struct GlucoseWidget_Previews: PreviewProvider {
    static var previews: some View {
        GlucoseView(entry: GlucoseEntry(date: Date(), glucose: placeholderLowGlucose, glucoseUnit: .mgdL))
            .previewContext(WidgetPreviewContext(family: .systemSmall))

        GlucoseView(entry: GlucoseEntry(date: Date(), glucose: placeholderLowGlucose, glucoseUnit: .mgdL))
            .previewContext(WidgetPreviewContext(family: .accessoryRectangular))

        GlucoseView(entry: GlucoseEntry(date: Date(), glucose: placeholderLowGlucose, glucoseUnit: .mmolL))
            .previewContext(WidgetPreviewContext(family: .accessoryRectangular))

        GlucoseView(entry: GlucoseEntry(date: Date(), glucose: placeholderGlucose, glucoseUnit: .mgdL))
            .previewContext(WidgetPreviewContext(family: .accessoryRectangular))

        GlucoseView(entry: GlucoseEntry(date: Date(), glucose: placeholderGlucose, glucoseUnit: .mmolL))
            .previewContext(WidgetPreviewContext(family: .accessoryRectangular))

        GlucoseView(entry: GlucoseEntry(date: Date(), glucose: placeholderHighGlucose, glucoseUnit: .mgdL))
            .previewContext(WidgetPreviewContext(family: .accessoryRectangular))

        GlucoseView(entry: GlucoseEntry(date: Date(), glucose: placeholderHighGlucose, glucoseUnit: .mmolL))
            .previewContext(WidgetPreviewContext(family: .accessoryRectangular))

        GlucoseView(entry: GlucoseEntry(date: Date(), glucose: placeholderHighGlucose, glucoseUnit: .mgdL))
            .previewContext(WidgetPreviewContext(family: .accessoryCircular))

        GlucoseView(entry: GlucoseEntry(date: Date(), glucose: placeholderHighGlucose, glucoseUnit: .mmolL))
            .previewContext(WidgetPreviewContext(family: .accessoryCircular))
    }
}
