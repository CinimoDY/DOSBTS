//
//  ExerciseEntry.swift
//  DOSBTS
//

import Foundation

// MARK: - ExerciseEntry

struct ExerciseEntry: CustomStringConvertible, Codable, Identifiable {
    // MARK: Lifecycle

    init(startTime: Date, endTime: Date, activityType: String, durationMinutes: Double, activeCalories: Double?, source: String?) {
        let roundedStart = startTime.toRounded(on: 1, .minute)

        self.id = UUID()
        self.startTime = roundedStart
        self.endTime = endTime.toRounded(on: 1, .minute)
        self.activityType = activityType
        self.durationMinutes = durationMinutes
        self.activeCalories = activeCalories
        self.source = source
        self.timegroup = roundedStart.toRounded(on: DirectConfig.timegroupRounding, .minute)
    }

    init(id: UUID, startTime: Date, endTime: Date, activityType: String, durationMinutes: Double, activeCalories: Double?, source: String?) {
        let roundedStart = startTime.toRounded(on: 1, .minute)

        self.id = id
        self.startTime = roundedStart
        self.endTime = endTime.toRounded(on: 1, .minute)
        self.activityType = activityType
        self.durationMinutes = durationMinutes
        self.activeCalories = activeCalories
        self.source = source
        self.timegroup = roundedStart.toRounded(on: DirectConfig.timegroupRounding, .minute)
    }

    // MARK: Internal

    let id: UUID
    let startTime: Date
    let endTime: Date
    let activityType: String
    let durationMinutes: Double
    let activeCalories: Double?
    let source: String?
    let timegroup: Date

    var description: String {
        "{ id: \(id), startTime: \(startTime.toLocalTime()), activityType: \(activityType), durationMinutes: \(durationMinutes) }"
    }
}

// MARK: Equatable

extension ExerciseEntry: Equatable {
    static func == (lhs: ExerciseEntry, rhs: ExerciseEntry) -> Bool {
        lhs.id == rhs.id
    }
}
