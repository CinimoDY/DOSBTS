//
//  SensorWidget.swift
//  DOSBTSWidget
//

import SwiftUI
import WidgetKit

private let placeholderSensor = Sensor(
    uuid: Data(hexString: "e9ad9b6c79bd93aa")!,
    patchInfo: Data(hexString: "448cd1")!,
    factoryCalibration: FactoryCalibration(i1: 1, i2: 2, i3: 4, i4: 8, i5: 16, i6: 32),
    family: .libre2,
    type: .virtual,
    region: .european,
    serial: "OBIR2PO",
    state: .ready,
    age: 3 * 24 * 60,
    lifetime: 14 * 24 * 60,
    warmupTime: 60
)

private let placeholderStartingSensor = Sensor(
    uuid: Data(hexString: "e9ad9b6c79bd93aa")!,
    patchInfo: Data(hexString: "448cd1")!,
    factoryCalibration: FactoryCalibration(i1: 1, i2: 2, i3: 4, i4: 8, i5: 16, i6: 32),
    family: .libre2,
    type: .virtual,
    region: .european,
    serial: "OBIR2PO",
    state: .starting,
    age: 20,
    lifetime: 14 * 24 * 60,
    warmupTime: 60
)

// MARK: - SensorEntry

struct SensorEntry: TimelineEntry {
    // MARK: Lifecycle

    init() {
        self.date = Date()
        self.sensor = nil
    }

    init(date: Date) {
        self.date = date
        self.sensor = nil
    }

    init(date: Date, sensor: Sensor) {
        self.date = date
        self.sensor = sensor
    }

    // MARK: Internal

    let date: Date
    let sensor: Sensor?
}

// MARK: - SensorUpdateProvider

struct SensorUpdateProvider: TimelineProvider {
    func placeholder(in context: Context) -> SensorEntry {
        return SensorEntry(date: Date(), sensor: placeholderSensor)
    }

    func getSnapshot(in context: Context, completion: @escaping (SensorEntry) -> ()) {
        let entry = SensorEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let entries = [SensorEntry()]
        let reloadDate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(15 * 60)
        let timeline = Timeline(entries: entries, policy: .after(reloadDate))
        completion(timeline)
    }
}

// MARK: - SensorView

struct SensorView: View {
    @Environment(\.widgetFamily) var size

    var entry: SensorEntry

    var sensor: Sensor? {
        entry.sensor ?? UserDefaults.shared.sensor
    }

    var body: some View {
        if let sensor {
            let remainingWarmupTime = sensor.remainingWarmupTime
            let isWarmup = remainingWarmupTime != nil
            let remaining = Double(isWarmup ? (remainingWarmupTime ?? 0) : sensor.remainingLifetime)
            let total = Double(isWarmup ? sensor.warmupTime : sensor.lifetime)
            let fraction = total > 0 ? remaining / total : 0

            ZStack {
                // Background arc track
                Circle()
                    .stroke(WidgetColors.amberDark.opacity(0.3), style: StrokeStyle(lineWidth: 6))

                // Filled arc
                Circle()
                    .trim(from: 0, to: CGFloat(fraction))
                    .stroke(
                        isWarmup ? WidgetColors.cgaCyan : WidgetColors.amber,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: (isWarmup ? WidgetColors.cgaCyan : WidgetColors.amber).opacity(0.4), radius: 3)

                // Center label
                VStack(spacing: 1) {
                    if isWarmup {
                        Text("WARM")
                            .font(WidgetFonts.tabBar)
                            .foregroundColor(WidgetColors.cgaCyan)
                    } else {
                        let days = sensor.remainingLifetime / (24 * 60)
                        let hours = (sensor.remainingLifetime % (24 * 60)) / 60
                        Text("\(days)d\(hours)h")
                            .font(WidgetFonts.mono(size: 13, weight: .bold))
                            .foregroundColor(WidgetColors.amber)
                    }
                    Text(sensor.family.localizedDescription)
                        .font(WidgetFonts.tabBar)
                        .foregroundColor(WidgetColors.amber)
                        .lineLimit(1)
                }
            }
            .padding(4)
            .widgetBackground(backgroundView: WidgetColors.dosBlack)
        } else {
            ZStack(alignment: .center) {
                Circle()
                    .stroke(style: StrokeStyle(lineWidth: 6, dash: [6, 3]))
                    .foregroundColor(WidgetColors.amberDark.opacity(0.3))

                Image(systemName: "questionmark")
                    .font(WidgetFonts.mono(size: 16, weight: .bold))
                    .foregroundColor(WidgetColors.amberDark)
            }
            .padding(4)
            .widgetBackground(backgroundView: WidgetColors.dosBlack)
        }
    }
}

// MARK: - SensorWidget

struct SensorWidget: Widget {
    let kind: String = "SensorWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SensorUpdateProvider()) { entry in
            SensorView(entry: entry)
        }
        .supportedFamilies([.accessoryCircular])
        .configurationDisplayName("Sensor")
        .description("Sensor remaining lifetime")
    }
}

// MARK: - SensorWidget_Previews

struct SensorWidget_Previews: PreviewProvider {
    static var previews: some View {
        SensorView(entry: SensorEntry(date: Date(), sensor: placeholderSensor))
            .previewContext(WidgetPreviewContext(family: .accessoryCircular))

        SensorView(entry: SensorEntry(date: Date(), sensor: placeholderStartingSensor))
            .previewContext(WidgetPreviewContext(family: .accessoryCircular))
    }
}
