//
//  ClinicReportMiddleware.swift
//  DOSBTSApp
//
//  Generates the clinic-visit report (DMNC-1304): on `.generateClinicReport`, fetch the
//  period's raw data + SQL statistics, assemble via `ClinicReportBuilder`, render a PDF or
//  write a CSV, and hand the file to the existing share path via `.sendFile`.
//
//  The share sheet is NOT this middleware's job — `.sendFile` is handled by logMiddleware's
//  SendService (iOS-26-safe scene lookup). `ImageRenderer` is MainActor-isolated, so the PDF
//  render hops to the main actor. Registered in BOTH middleware arrays in App.swift.
//

import Combine
import Foundation
import SwiftUI

func clinicReportMiddleware() -> Middleware<DirectState, DirectAction> {
    return { state, action, _ in
        switch action {
        case let .generateClinicReport(days, format):
            guard state.appState == .active else { break }

            let glucoseUnit = state.glucoseUnit
            let appBuild = DirectConfig.appBuild

            return Publishers.Zip(
                DataStore.shared.getClinicReportData(days: days),
                // Consensus TIR band (70–180), NOT the user's alarm profile — a clinician
                // expects the standard band or the report is non-comparable.
                DataStore.shared.clinicGlucoseStatistics(days: days, lowerLimit: 70, upperLimit: 180)
            )
            .flatMap { raw, statistics -> AnyPublisher<DirectAction, DirectError> in
                let data = ClinicReportBuilder.assemble(statistics: statistics, raw: raw)
                return Future<DirectAction, DirectError> { promise in
                    switch format {
                    case .csv:
                        if let url = ClinicReportFile.writeCSV(data: data, glucoseUnit: glucoseUnit) {
                            promise(.success(.sendFile(fileURL: url)))
                        } else {
                            promise(.failure(.withMessage("Clinic report: cannot create CSV")))
                        }

                    case .pdf:
                        // ImageRenderer is MainActor-isolated — render on the main actor, then resume.
                        DispatchQueue.main.async {
                            let url = MainActor.assumeIsolated {
                                ClinicReportFile.renderPDF(data: data, glucoseUnit: glucoseUnit, appBuild: appBuild)
                            }
                            if let url {
                                promise(.success(.sendFile(fileURL: url)))
                            } else {
                                promise(.failure(.withMessage("Clinic report: cannot render PDF")))
                            }
                        }
                    }
                }.eraseToAnyPublisher()
            }
            .catch { error -> Just<DirectAction> in
                // Clear the busy flag the reducer set on .generateClinicReport (a bare
                // failure would strand it — the export middlewares have this latent gap).
                DirectLog.error("Clinic report generation failed: \(error)")
                return Just(.setAppIsBusy(isBusy: false))
            }
            .setFailureType(to: DirectError.self)
            .eraseToAnyPublisher()

        default:
            break
        }

        return Empty().eraseToAnyPublisher()
    }
}

// MARK: - ClinicReportFile

/// File builders for the clinic report. CSV reuses the shared `createFile`/`writeFile`
/// machinery (with its CSV-injection-safe escaping); PDF renders the DOS-styled page.
enum ClinicReportFile {

    private static func isoDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX") // locale-stable columns for the clinic
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    // MARK: CSV

    static func writeCSV(data: ClinicReportData, glucoseUnit _: GlucoseUnit) -> URL? {
        guard let url = createFile(filename: "dosbts-clinic-report") else { return nil }
        let statistics = data.statistics
        let dateFormatter = isoDateFormatter()

        func mmol(_ mgdl: Int) -> String { String(format: "%.1f", mgdl.toMmolL()) }

        var rows: [[String]] = []
        rows.append(["DOSBTS CLINIC REPORT"])
        rows.append(["Period", dateFormatter.string(from: data.period.start), dateFormatter.string(from: data.period.end)])
        rows.append(["Readings", "\(statistics.readings)"])
        rows.append(["Days of coverage", "\(statistics.days)"])
        rows.append([])

        rows.append(["STATISTICS", "mg/dL", "mmol/L"])
        if data.hasSufficientData {
            rows.append(["Avg glucose", "\(Int(statistics.avg.rounded()))", mmol(Int(statistics.avg.rounded()))])
            rows.append(["Std dev", "\(Int(statistics.stdev.rounded()))", mmol(Int(statistics.stdev.rounded()))])
            rows.append(["CV %", String(format: "%.1f", statistics.cv), ""])
            rows.append(["GMI %", String(format: "%.1f", statistics.gmi), ""])
        } else {
            rows.append(["INSUFFICIENT DATA", "", ""])
        }
        rows.append([])

        rows.append(["TIME IN RANGE (70-180 consensus)", "%"])
        rows.append(["In range", String(format: "%.1f", statistics.tir)])
        rows.append(["Below range", String(format: "%.1f", statistics.tbr)])
        rows.append(["Above range", String(format: "%.1f", statistics.tar)])
        rows.append([])

        rows.append(["HOURLY PATTERN", "median mg/dL", "median mmol/L", "p25 mg/dL", "p75 mg/dL", "readings"])
        for row in data.hourlyPatterns {
            rows.append([
                String(format: "%02d:00", row.hour),
                row.median.map { "\($0)" } ?? "",
                row.median.map(mmol) ?? "",
                row.p25.map { "\($0)" } ?? "",
                row.p75.map { "\($0)" } ?? "",
                "\(row.readings)",
            ])
        }
        rows.append([])

        rows.append(["EVENTS", "count"])
        rows.append(["Meals logged", "\(data.mealCount)"])
        rows.append(["Meal boluses", "\(data.bolusCounts[.mealBolus] ?? 0)"])
        rows.append(["Snack boluses", "\(data.bolusCounts[.snackBolus] ?? 0)"])
        rows.append(["Correction boluses", "\(data.bolusCounts[.correctionBolus] ?? 0)"])
        rows.append(["Basal entries", "\(data.basalCount)"])
        rows.append(["Hypo episodes (<70 mg/dL, >=15 min)", "\(data.hypoEpisodeCount)"])

        writeFile(temporaryURL: url, values: rows)
        return url
    }

    // MARK: PDF

    @MainActor
    static func renderPDF(data: ClinicReportData, glucoseUnit: GlucoseUnit, appBuild: String) -> URL? {
        let page = ClinicReportPage(data: data, glucoseUnit: glucoseUnit, appBuild: appBuild, generatedAt: Date())
        let renderer = ImageRenderer(content: page)

        let fileManager = FileManager.default
        let directory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = directory.appendingPathComponent("dosbts-clinic-report.pdf")
        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }

        var didWrite = false
        renderer.render { size, renderInContext in
            var box = CGRect(origin: .zero, size: size)
            guard let pdfContext = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdfContext.beginPDFPage(nil)
            renderInContext(pdfContext)
            pdfContext.endPDFPage()
            pdfContext.closePDF()
            didWrite = true
        }
        return didWrite ? url : nil
    }
}
