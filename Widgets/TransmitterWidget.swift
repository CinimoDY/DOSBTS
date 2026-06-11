//
//  TransmitterWidget.swift
//  DOSBTSWidget
//

import SwiftUI
import WidgetKit

private let placeholderTransmitter = Transmitter(name: "Bubble", battery: 70, firmware: 2.0, hardware: 2.0)

// MARK: - TransmitterEntry

struct TransmitterEntry: TimelineEntry {
    // MARK: Lifecycle

    init() {
        self.date = Date()
        self.transmitter = nil
    }

    init(date: Date) {
        self.date = date
        self.transmitter = nil
    }

    init(date: Date, transmitter: Transmitter) {
        self.date = date
        self.transmitter = transmitter
    }

    // MARK: Internal

    let date: Date
    let transmitter: Transmitter?
}

// MARK: - TransmitterUpdateProvider

struct TransmitterUpdateProvider: TimelineProvider {
    func placeholder(in context: Context) -> TransmitterEntry {
        return TransmitterEntry(date: Date(), transmitter: placeholderTransmitter)
    }

    func getSnapshot(in context: Context, completion: @escaping (TransmitterEntry) -> ()) {
        let entry = TransmitterEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let entries = [TransmitterEntry()]
        let reloadDate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(15 * 60)
        let timeline = Timeline(entries: entries, policy: .after(reloadDate))
        completion(timeline)
    }
}

// MARK: - TransmitterView

struct TransmitterView: View {
    @Environment(\.widgetFamily) var size

    var entry: TransmitterEntry

    var transmitter: Transmitter? {
        entry.transmitter ?? UserDefaults.shared.transmitter
    }

    var body: some View {
        if let transmitter {
            let fraction = Double(transmitter.battery) / 100.0
            let batteryColor = transmitter.battery > 20 ? WidgetColors.amber : WidgetColors.cgaRed

            ZStack {
                // Background arc track
                Circle()
                    .stroke(WidgetColors.amberDark.opacity(0.3), style: StrokeStyle(lineWidth: 6))

                // Filled arc
                Circle()
                    .trim(from: 0, to: CGFloat(fraction))
                    .stroke(
                        batteryColor,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: batteryColor.opacity(0.4), radius: 3)

                // Center label
                VStack(spacing: 1) {
                    Text("\(transmitter.battery)%")
                        .font(WidgetFonts.mono(size: 13, weight: .bold))
                        .foregroundColor(batteryColor)

                    Text(transmitter.name)
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

// MARK: - TransmitterWidget

struct TransmitterWidget: Widget {
    let kind: String = "TransmitterWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TransmitterUpdateProvider()) { entry in
            TransmitterView(entry: entry)
        }
        .supportedFamilies([.accessoryCircular])
        .configurationDisplayName("Transmitter")
        .description("Transmitter battery level")
    }
}

// MARK: - TransmitterWidget_Previews

struct TransmitterWidget_Previews: PreviewProvider {
    static var previews: some View {
        TransmitterView(entry: TransmitterEntry(date: Date(), transmitter: placeholderTransmitter))
            .previewContext(WidgetPreviewContext(family: .accessoryCircular))
    }
}
