//
//  DailyDigest.swift
//  DOSBTS
//

import Foundation

// MARK: - DailyDigest

struct DailyDigest: Codable, Identifiable {
    // MARK: Lifecycle

    init(date: Date, tir: Double, tbr: Double, tar: Double, avg: Double, stdev: Double, readings: Int, lowCount: Int, highCount: Int, totalCarbsGrams: Double, totalInsulinUnits: Double, totalExerciseMinutes: Double, mealCount: Int, insulinCount: Int, aiInsight: String? = nil, generatedAt: Date? = nil) {
        self.id = UUID()
        self.date = date
        self.tir = tir
        self.tbr = tbr
        self.tar = tar
        self.avg = avg
        self.stdev = stdev
        self.readings = readings
        self.lowCount = lowCount
        self.highCount = highCount
        self.totalCarbsGrams = totalCarbsGrams
        self.totalInsulinUnits = totalInsulinUnits
        self.totalExerciseMinutes = totalExerciseMinutes
        self.mealCount = mealCount
        self.insulinCount = insulinCount
        self.aiInsight = aiInsight
        self.generatedAt = generatedAt
    }

    // MARK: Internal

    let id: UUID
    let date: Date
    let tir: Double
    let tbr: Double
    let tar: Double
    let avg: Double
    let stdev: Double
    let readings: Int
    let lowCount: Int
    let highCount: Int
    let totalCarbsGrams: Double
    let totalInsulinUnits: Double
    let totalExerciseMinutes: Double
    let mealCount: Int
    let insulinCount: Int
    var aiInsight: String?
    var generatedAt: Date?
}

// MARK: Equatable

extension DailyDigest: Equatable {
    static func == (lhs: DailyDigest, rhs: DailyDigest) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - DailyDigestEvents

struct DailyDigestEvents {
    let meals: [MealEntry]
    let insulin: [InsulinDelivery]
    let exercise: [ExerciseEntry]
    /// `var` with a default rather than `let` so it lands in the memberwise
    /// initializer as an optional argument — the empty-events construction
    /// sites keep compiling unchanged.
    var notes: [JournalNote] = []
}
