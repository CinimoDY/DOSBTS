//
//  ClinicReportPage.swift
//  DOSBTSApp
//
//  Fixed-width (A4) DOS-styled page rendered to PDF by `ImageRenderer` (DMNC-1304).
//  The terminal look (black background, amber text) is intentional — "no real white"
//  is a design-system rule and dark PDFs print fine; it's the product's identity.
//  Design-system tokens only (StyleGuard scans this file).
//

import SwiftUI

struct ClinicReportPage: View {
    let data: ClinicReportData
    let glucoseUnit: GlucoseUnit
    let appBuild: String
    let generatedAt: Date

    /// A4 width at 72 dpi. Height flows with content (single page, no clipping).
    private static let pageWidth: CGFloat = 595

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: DOSSpacing.md) {
            header
            statsBlock
            tirBlock
            hourlyBlock
            eventsBlock
            footer
        }
        .padding(DOSSpacing.lg)
        .frame(width: Self.pageWidth, alignment: .leading)
        .background(AmberTheme.dosBlack)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("DOSBTS CLINIC REPORT")
                .font(DOSTypography.mono(size: 20, weight: .bold))
                .foregroundStyle(AmberTheme.amber)
            Text("PERIOD \(Self.dateFormatter.string(from: data.period.start)) — \(Self.dateFormatter.string(from: data.period.end))")
                .font(DOSTypography.caption)
                .foregroundStyle(AmberTheme.amberDark)
            Text("GENERATED \(Self.dateFormatter.string(from: generatedAt)) · BUILD \(appBuild)")
                .font(DOSTypography.caption)
                .foregroundStyle(AmberTheme.amberDark)
        }
    }

    // MARK: Statistics

    private var statsBlock: some View {
        VStack(alignment: .leading, spacing: DOSSpacing.xxs) {
            Text("STATISTICS").dosHeader()
            if data.hasSufficientData {
                statRow("AVG GLUCOSE", glucose(Int(data.statistics.avg.rounded())))
                statRow("STD DEV", glucose(Int(data.statistics.stdev.rounded())))
                statRow("CV", String(format: "%.1f%%", data.statistics.cv))
                statRow("GMI", String(format: "%.1f%%", data.statistics.gmi))
            } else {
                Text("INSUFFICIENT DATA")
                    .font(DOSTypography.bodySmall)
                    .foregroundStyle(AmberTheme.cgaRed)
            }
            statRow("READINGS", "\(data.statistics.readings)")
            if data.statistics.days < ReportPeriod.twoWeeks.days {
                Text("INSUFFICIENT DATA — ONLY \(data.statistics.days) DAYS OF COVERAGE")
                    .font(DOSTypography.micro)
                    .foregroundStyle(AmberTheme.cgaRed)
            }
        }
    }

    // MARK: Time in range

    private var tirBlock: some View {
        VStack(alignment: .leading, spacing: DOSSpacing.xxs) {
            Text("TIME IN RANGE").dosHeader()
            tirBar("IN RANGE", data.statistics.tir, AmberTheme.cgaGreen)
            tirBar("BELOW RANGE", data.statistics.tbr, AmberTheme.cgaRed)
            tirBar("ABOVE RANGE", data.statistics.tar, AmberTheme.amber)
            Text("TIR BAND 70–180 MG/DL (CONSENSUS)")
                .font(DOSTypography.micro)
                .foregroundStyle(AmberTheme.amberDark)
        }
    }

    private func tirBar(_ label: String, _ percent: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(DOSTypography.caption)
                    .foregroundStyle(AmberTheme.amber)
                Spacer()
                Text(String(format: "%.0f%%", percent))
                    .font(DOSTypography.caption)
                    .foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(AmberTheme.surfaceTint)
                    Rectangle().fill(color)
                        .frame(width: geo.size.width * min(1, max(0, percent / 100)))
                }
            }
            .frame(height: 8)
        }
    }

    // MARK: Hourly pattern

    private var hourlyBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("HOURLY PATTERN").dosHeader()
            HStack {
                Text("HOUR").frame(width: 70, alignment: .leading)
                Text("MEDIAN").frame(width: 90, alignment: .trailing)
                Text("P25–P75").frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(DOSTypography.micro)
            .foregroundStyle(AmberTheme.amberDark)
            ForEach(data.hourlyPatterns, id: \.hour) { row in
                HStack {
                    Text(String(format: "%02d:00", row.hour))
                        .frame(width: 70, alignment: .leading)
                    Text(row.median.map(glucose) ?? "—")
                        .frame(width: 90, alignment: .trailing)
                    Text(rangeText(row))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(DOSTypography.caption)
                .foregroundStyle(row.readings > 0 ? AmberTheme.amber : AmberTheme.amberDark)
            }
        }
    }

    private func rangeText(_ row: HourlyPattern) -> String {
        guard let p25 = row.p25, let p75 = row.p75 else { return "—" }
        return "\(glucose(p25))–\(glucose(p75))"
    }

    // MARK: Events

    private var eventsBlock: some View {
        VStack(alignment: .leading, spacing: DOSSpacing.xxs) {
            Text("EVENTS").dosHeader()
            statRow("MEALS LOGGED", "\(data.mealCount)")
            statRow("MEAL BOLUSES", "\(data.bolusCounts[.mealBolus] ?? 0)")
            statRow("SNACK BOLUSES", "\(data.bolusCounts[.snackBolus] ?? 0)")
            statRow("CORRECTION BOLUSES", "\(data.bolusCounts[.correctionBolus] ?? 0)")
            statRow("BASAL ENTRIES", "\(data.basalCount)")
            statRow("HYPO EPISODES (<70, ≥15 MIN)", "\(data.hypoEpisodeCount)")
        }
    }

    // MARK: Footer

    private var footer: some View {
        Text("Pseudonymous educational summary generated by DOSBTS. Not a medical device. Discuss all values with your care team.")
            .font(DOSTypography.micro)
            .foregroundStyle(AmberTheme.amberDark)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Helpers

    private func glucose(_ mgdl: Int) -> String { mgdl.asGlucose(glucoseUnit: glucoseUnit) }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(DOSTypography.caption)
                .foregroundStyle(AmberTheme.amber)
            Spacer()
            Text(value)
                .font(DOSTypography.bodySmall)
                .foregroundStyle(AmberTheme.amberLight)
        }
    }
}
