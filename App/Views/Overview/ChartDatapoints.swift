//
//  ChartDatapoints.swift
//  DOSBTS
//
//  Chart-local plotting models and the domain→datapoint mapping extensions
//  used by ChartView. Extracted from ChartView.swift (DMNC hygiene split);
//  only the chart reads these types.
//

import SwiftUI

// MARK: - ZoomLevel

struct ZoomLevel {
    let level: Int
    let name: String
    let visibleHours: Int
    let labelEvery: Int
}

// MARK: Equatable

extension ZoomLevel: Equatable {
    static func == (lhs: ZoomLevel, rhs: ZoomLevel) -> Bool {
        lhs.level == rhs.level
    }
}

// MARK: - GlucoseDatapoint

struct GlucoseDatapoint: Identifiable {
    let id: String
    let time: Date
    let value: Double
    let info: String
    var level: String = "inRange"
}

// MARK: Equatable

extension GlucoseDatapoint: Equatable {
    static func == (lhs: GlucoseDatapoint, rhs: GlucoseDatapoint) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - GlucoseSegment

struct GlucoseSegment: Identifiable {
    let id: String
    let level: String
    let points: [GlucoseDatapoint]

    var color: Color {
        switch level {
        case "low": return AmberTheme.cgaRed
        case "lowBuffer": return AmberTheme.glucoseLowBuffer
        case "inRange": return AmberTheme.cgaGreen
        case "rising": return AmberTheme.glucoseRising
        case "approaching": return AmberTheme.amber
        case "highBuffer": return AmberTheme.glucoseHighBuffer
        case "high": return AmberTheme.cgaRed
        default: return AmberTheme.cgaGreen
        }
    }
}

/// Splits a glucose series into contiguous segments by level,
/// with one overlapping boundary point so lines connect across transitions.
func segmentGlucoseSeries(_ series: [GlucoseDatapoint]) -> [GlucoseSegment] {
    guard !series.isEmpty else { return [] }

    var segments: [GlucoseSegment] = []
    var currentLevel = series[0].level
    var currentPoints: [GlucoseDatapoint] = [series[0]]

    for i in 1..<series.count {
        let point = series[i]
        if point.level == currentLevel {
            currentPoints.append(point)
        } else {
            // Include this boundary point in the current segment so the line reaches it
            currentPoints.append(point)
            segments.append(GlucoseSegment(
                id: "seg-\(segments.count)-\(currentLevel)",
                level: currentLevel,
                points: currentPoints
            ))
            // Start new segment from previous point (overlap) so the new line starts connected
            currentPoints = [series[i - 1], point]
            currentLevel = point.level
        }
    }

    if !currentPoints.isEmpty {
        segments.append(GlucoseSegment(
            id: "seg-\(segments.count)-\(currentLevel)",
            level: currentLevel,
            points: currentPoints
        ))
    }

    return segments
}

// MARK: - InsulinDatapoint

struct InsulinDatapoint: Identifiable {
    let id: String
    let starts: Date
    let ends: Date
    let value: Double
    let type: InsulinType
    let info: String
}

// MARK: - MealDatapoint

struct MealDatapoint: Identifiable {
    let id: String
    let time: Date
    let label: String
    let carbs: Double?
}

extension MealEntry {
    func toDatapoint() -> MealDatapoint {
        return MealDatapoint(
            id: id.uuidString,
            time: timestamp,
            label: mealDescription,
            carbs: carbsGrams
        )
    }
}

// MARK: - ExerciseDatapoint

struct ExerciseDatapoint: Identifiable {
    let id: String
    let startTime: Date
    let endTime: Date
    let activityType: String
}

extension ExerciseEntry {
    func toDatapoint() -> ExerciseDatapoint {
        return ExerciseDatapoint(
            id: id.uuidString,
            startTime: startTime,
            endTime: endTime,
            activityType: activityType
        )
    }
}

extension InsulinDelivery {
    func toDatapoint(minDate: Date, maxDate: Date) -> InsulinDatapoint {
        return InsulinDatapoint(
            id: id.uuidString,
            starts: max(minDate, starts),
            ends: min(maxDate, ends),
            value: units,
            type: type,
            info: type.localizedDescription
        )
    }
}

extension BloodGlucose {
    func toDatapointID(glucoseUnit: GlucoseUnit) -> String {
        "\(id.uuidString)-\(glucoseUnit.rawValue)"
    }

    func toDatapoint(glucoseUnit: GlucoseUnit, alarmLow: Int, alarmHigh: Int) -> GlucoseDatapoint {
        if glucoseUnit == .mmolL {
            return GlucoseDatapoint(
                id: toDatapointID(glucoseUnit: glucoseUnit),
                time: timestamp,
                value: glucoseValue.toMmolL(),
                info: glucoseValue.asGlucose(glucoseUnit: glucoseUnit, withUnit: true)
            )
        }

        return GlucoseDatapoint(
            id: toDatapointID(glucoseUnit: glucoseUnit),
            time: timestamp,
            value: glucoseValue.toDouble(),
            info: glucoseValue.asGlucose(glucoseUnit: glucoseUnit, withUnit: true)
        )
    }
}

extension SensorGlucose {
    func toDatapointID(glucoseUnit: GlucoseUnit) -> String {
        "\(id.uuidString)-\(glucoseUnit.rawValue)"
    }

    func toRawDatapoint(glucoseUnit: GlucoseUnit, alarmLow: Int, alarmHigh: Int, shiftY: Int = 0) -> GlucoseDatapoint {
        if glucoseUnit == .mmolL {
            return GlucoseDatapoint(
                id: toDatapointID(glucoseUnit: glucoseUnit),
                time: timestamp,
                value: rawGlucoseValue.toMmolL() + shiftY.toMmolL(),
                info: rawGlucoseValue.asGlucose(glucoseUnit: glucoseUnit, withUnit: true)
            )
        }

        return GlucoseDatapoint(
            id: toDatapointID(glucoseUnit: glucoseUnit),
            time: timestamp,
            value: rawGlucoseValue.toDouble() + shiftY.toDouble(),
            info: rawGlucoseValue.asGlucose(glucoseUnit: glucoseUnit, withUnit: true)
        )
    }

    func toSmoothDatapoint(glucoseUnit: GlucoseUnit, alarmLow: Int, alarmHigh: Int, shiftY: Int = 0) -> GlucoseDatapoint {
        let glucose = (smoothGlucoseValue ?? Double(glucoseValue))
        let info = glucose.toInteger()?.asGlucose(glucoseUnit: glucoseUnit, withUnit: true) ?? ""
        let level = AmberTheme.glucoseLevel(forValue: Int(glucose), low: alarmLow, high: alarmHigh)

        if glucoseUnit == .mmolL {
            return GlucoseDatapoint(
                id: toDatapointID(glucoseUnit: glucoseUnit),
                time: timestamp,
                value: glucose.toMmolL() + shiftY.toMmolL(),
                info: info,
                level: level
            )
        }

        return GlucoseDatapoint(
            id: toDatapointID(glucoseUnit: glucoseUnit),
            time: timestamp,
            value: glucose + shiftY.toDouble(),
            info: info,
            level: level
        )
    }

    func toDatapoint(glucoseUnit: GlucoseUnit, alarmLow: Int, alarmHigh: Int, shiftY: Int = 0) -> GlucoseDatapoint {
        var info: String

        if let minuteChange = minuteChange {
            info = "\(glucoseValue.asGlucose(glucoseUnit: glucoseUnit, withUnit: true)) \(minuteChange.asMinuteChange(glucoseUnit: glucoseUnit))"
        } else {
            info = glucoseValue.asGlucose(glucoseUnit: glucoseUnit, withUnit: true)
        }

        let level = AmberTheme.glucoseLevel(forValue: glucoseValue, low: alarmLow, high: alarmHigh)

        if glucoseUnit == .mmolL {
            return GlucoseDatapoint(
                id: toDatapointID(glucoseUnit: glucoseUnit),
                time: timestamp,
                value: glucoseValue.toMmolL() + shiftY.toMmolL(),
                info: info,
                level: level
            )
        }

        return GlucoseDatapoint(
            id: toDatapointID(glucoseUnit: glucoseUnit),
            time: timestamp,
            value: glucoseValue.toDouble() + shiftY.toDouble(),
            info: info,
            level: level
        )
    }
}
