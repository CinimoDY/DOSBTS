//
//  LabChartDescriptor.swift
//  DOSBTS
//
//  Chart Lab (DMNC-1500 / P5): the app's FIRST `AXChartDescriptor`.
//
//  The same facts that print as pins, a sheet line and cards are what VoiceOver
//  reads — the sheet line IS the chart's summary, so a screen-reader user gets
//  the cited numbers rather than "chart" and a wall of unlabelled points. The
//  Audio Graph rotor gets the glucose trace as a continuous series and each
//  cited fact as a labelled point.
//

import Accessibility
import SwiftUI

// MARK: - LabChartAccessibility

enum LabChartAccessibility {
    /// What VoiceOver says when it lands on the chart. Pure, so the copy is
    /// pinned by tests.
    static func summary(sheet: ChartFeatureSheet?, facts: [ChartFact], unit: GlucoseUnit) -> String {
        guard let sheet, sheet.readings > 0 else {
            return "Lab chart. No readings to plot."
        }

        let line = LabCaption.text(for: sheet.items(), unit: unit)
        let cited: String
        switch facts.count {
        case 0: cited = "No cited facts."
        case 1: cited = "1 cited fact."
        default: cited = "\(facts.count) cited facts."
        }
        return "Lab chart. \(line). \(cited)"
    }
}

// MARK: - LabChartDescriptor

struct LabChartDescriptor: AXChartDescriptorRepresentable {
    let series: LabChartSeries
    let facts: [ChartFact]
    let sheet: ChartFeatureSheet?
    let glucoseUnit: GlucoseUnit

    func makeChartDescriptor() -> AXChartDescriptor {
        let points = series.glucose
        let times = points.map(\.time.timeIntervalSinceReferenceDate)
        let values = points.map(\.value)

        let xAxis = AXNumericDataAxisDescriptor(
            title: "Time",
            range: (times.min() ?? 0) ... (times.max() ?? 1),
            gridlinePositions: []
        ) { value in
            Date(timeIntervalSinceReferenceDate: value).toLocalTime()
        }

        let yAxis = AXNumericDataAxisDescriptor(
            title: "Glucose",
            range: (values.min() ?? 0) ... (values.max() ?? 1),
            gridlinePositions: []
        ) { value in
            "\(value.formatted()) \(glucoseUnit.localizedDescription)"
        }

        var descriptorSeries: [AXDataSeriesDescriptor] = [
            AXDataSeriesDescriptor(
                name: "Glucose",
                isContinuous: true,
                dataPoints: zip(times, values).map { AXDataPoint(x: $0, y: $1) }
            )
        ]

        if !facts.isEmpty {
            descriptorSeries.append(AXDataSeriesDescriptor(
                name: "Cited facts",
                isContinuous: false,
                dataPoints: facts.map { fact in
                    AXDataPoint(
                        x: fact.anchor.timeIntervalSinceReferenceDate,
                        y: series.nearestGlucose(at: fact.anchor)?.value,
                        label: factLabel(fact)
                    )
                }
            ))
        }

        return AXChartDescriptor(
            title: "Lab chart",
            summary: LabChartAccessibility.summary(sheet: sheet, facts: facts, unit: glucoseUnit),
            xAxis: xAxis,
            yAxis: yAxis,
            series: descriptorSeries
        )
    }

    // MARK: Private

    /// The card, spoken: its title and every line it prints.
    private func factLabel(_ fact: ChartFact) -> String {
        ([LabCaption.text(for: fact.title, unit: glucoseUnit)]
            + fact.lines.map { LabCaption.text(for: $0, unit: glucoseUnit) })
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
    }
}
