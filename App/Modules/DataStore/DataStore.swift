//
//  DataStore.swift
//  DOSBTSApp
//
//  https://github.com/groue/GRDB.swift
//

import Combine
import Foundation
import GRDB

// MARK: - DataStore

class DataStore {
    // MARK: Lifecycle

    private init() {
        do {
            dbQueue = try DatabaseQueue(path: databaseURL.path)
        } catch {
            DirectLog.error("\(error)")
            dbQueue = nil
        }
    }

    deinit {
        do {
            try dbQueue?.close()
        } catch {
            DirectLog.error("\(error)")
        }
    }

    // MARK: Internal

    static let shared = DataStore()

    let dbQueue: DatabaseQueue?

    var databaseURL: URL = {
        let filename = "GlucoseDirect.sqlite"
        let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        return documentDirectory.appendingPathComponent(filename)
    }()

    func deleteDatabase() {
        do {
            try FileManager.default.removeItem(at: databaseURL)
        } catch _ {}
    }
}

// MARK: - SensorGlucose + FetchableRecord, PersistableRecord

extension SensorGlucose: FetchableRecord, PersistableRecord {
    static let databaseUUIDEncodingStrategy = DatabaseUUIDEncodingStrategy.uppercaseString

    static var Table: String {
        "SensorGlucose"
    }

    enum Columns: String, ColumnExpression {
        case id
        case timestamp
        case minuteChange
        case rawGlucoseValue
        case intGlucoseValue
        case smoothGlucoseValue
        case timegroup
    }
}

// MARK: - BloodGlucose + FetchableRecord, PersistableRecord

extension BloodGlucose: FetchableRecord, PersistableRecord {
    static let databaseUUIDEncodingStrategy = DatabaseUUIDEncodingStrategy.uppercaseString

    static var Table: String {
        "BloodGlucose"
    }

    enum Columns: String, ColumnExpression {
        case id
        case timestamp
        case glucoseValue
        case timegroup
    }
}

// MARK: - SensorError + FetchableRecord, PersistableRecord

extension SensorError: FetchableRecord, PersistableRecord {
    static let databaseUUIDEncodingStrategy = DatabaseUUIDEncodingStrategy.uppercaseString

    static var Table: String {
        "SensorError"
    }

    enum Columns: String, ColumnExpression {
        case id
        case timestamp
        case error
        case timegroup
    }
}

// MARK: - InsulinDelivery + FetchableRecord, PersistableRecord

extension InsulinDelivery: FetchableRecord, PersistableRecord {
    static let databaseUUIDEncodingStrategy = DatabaseUUIDEncodingStrategy.uppercaseString

    static var Table: String {
        "InsulinDelivery"
    }

    enum Columns: String, ColumnExpression {
        case id
        case starts
        case ends
        case units
        case type
        case timegroup
    }
}

// MARK: - ExerciseEntry + FetchableRecord, PersistableRecord

extension ExerciseEntry: FetchableRecord, PersistableRecord {
    static let databaseUUIDEncodingStrategy = DatabaseUUIDEncodingStrategy.uppercaseString

    static var Table: String {
        "ExerciseEntry"
    }

    enum Columns: String, ColumnExpression {
        case id
        case startTime
        case endTime
        case activityType
        case durationMinutes
        case activeCalories
        case source
        case timegroup
    }
}

// MARK: - FoodCorrection + FetchableRecord, PersistableRecord

extension FoodCorrection: FetchableRecord, PersistableRecord {
    static let databaseUUIDEncodingStrategy = DatabaseUUIDEncodingStrategy.uppercaseString

    static var Table: String {
        "FoodCorrection"
    }

    enum Columns: String, ColumnExpression {
        case id
        case timestamp
        case correctionType
        case originalName
        case correctedName
        case originalCarbsG
        case correctedCarbsG
    }
}

// MARK: - PersonalFood + FetchableRecord, PersistableRecord

extension PersonalFood: FetchableRecord, PersistableRecord {
    static let databaseUUIDEncodingStrategy = DatabaseUUIDEncodingStrategy.uppercaseString

    static var Table: String {
        "PersonalFood"
    }

    enum Columns: String, ColumnExpression {
        case id
        case name
        case carbsG
        case lastUsed
        case analysisSessionId
        case avgDeltaMgDL
        case observationCount
        case lastScoredDate
    }
}

// MARK: - FoodCorrection.CorrectionType + DatabaseValueConvertible

extension FoodCorrection.CorrectionType: DatabaseValueConvertible {}

// MARK: - FavoriteFood + FetchableRecord, PersistableRecord

extension FavoriteFood: FetchableRecord, PersistableRecord {
    static let databaseUUIDEncodingStrategy = DatabaseUUIDEncodingStrategy.uppercaseString

    static var Table: String {
        "FavoriteFood"
    }

    enum Columns: String, ColumnExpression {
        case id
        case mealDescription
        case carbsGrams
        case proteinGrams
        case fatGrams
        case calories
        case fiberGrams
        case sortOrder
        case isHypoTreatment
        case lastUsed
        case shortLabel
    }
}

// MARK: - TreatmentEvent + FetchableRecord, PersistableRecord

extension TreatmentEvent: FetchableRecord, PersistableRecord {
    static let databaseUUIDEncodingStrategy = DatabaseUUIDEncodingStrategy.uppercaseString

    static var Table: String {
        "TreatmentEvent"
    }

    enum Columns: String, ColumnExpression {
        case id
        case mealEntryId
        case alarmFiredAt
        case treatmentLoggedAt
        case treatmentType
        case glucoseAtTreatment
        case countdownMinutes
        case timegroup
    }
}

// MARK: - MealEntry + FetchableRecord, PersistableRecord

extension MealEntry: FetchableRecord, PersistableRecord {
    static let databaseUUIDEncodingStrategy = DatabaseUUIDEncodingStrategy.uppercaseString

    static var Table: String {
        "MealEntry"
    }

    enum Columns: String, ColumnExpression {
        case id
        case timestamp
        case mealDescription
        case carbsGrams
        case proteinGrams
        case fatGrams
        case calories
        case fiberGrams
        case timegroup
        case analysisSessionId
    }
}

// MARK: - MealImpact + FetchableRecord, PersistableRecord

extension MealImpact: FetchableRecord, PersistableRecord {
    static let databaseUUIDEncodingStrategy = DatabaseUUIDEncodingStrategy.uppercaseString

    static var Table: String {
        "MealImpact"
    }

    enum Columns: String, ColumnExpression {
        case id
        case mealEntryId
        case baselineGlucose
        case peakGlucose
        case deltaMgDL
        case timeToPeakMinutes
        case isClean
        case timestamp
    }
}

// MARK: - DailyDigest + FetchableRecord, PersistableRecord

extension DailyDigest: FetchableRecord, PersistableRecord {
    static let databaseUUIDEncodingStrategy = DatabaseUUIDEncodingStrategy.uppercaseString

    static var Table: String {
        "DailyDigest"
    }

    enum Columns: String, ColumnExpression {
        case id
        case date
        case tir
        case tbr
        case tar
        case avg
        case stdev
        case readings
        case lowCount
        case highCount
        case totalCarbsGrams
        case totalInsulinUnits
        case totalExerciseMinutes
        case mealCount
        case insulinCount
        case aiInsight
        case generatedAt
    }
}

// MARK: - JournalNote + FetchableRecord, PersistableRecord

extension JournalNote: FetchableRecord, PersistableRecord {
    static let databaseUUIDEncodingStrategy = DatabaseUUIDEncodingStrategy.uppercaseString

    static var Table: String {
        "JournalNote"
    }

    enum Columns: String, ColumnExpression {
        case id
        case timestamp
        case text
        case tag
    }
}

// MARK: - JournalNoteTag + DatabaseValueConvertible

extension JournalNoteTag: DatabaseValueConvertible {}
