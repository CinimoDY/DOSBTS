//
//  PayloadMapperTests.swift
//  DOSBTSTests
//
//  Pins the pure widget/Nightscout payload mappers (DMNC-1405): key sets, values, and
//  JSON-serializability. These feed the silent guard-return upload sites — a regression
//  that makes a payload non-serializable (e.g. a raw Date/UUID) now fails here at Cmd+U
//  instead of silently dropping a widget update or Nightscout upload at runtime.
//

import Foundation
import Testing
@testable import DOSBTSApp

// MARK: - Helpers

/// True iff `JSONSerialization` would accept the payload — the exact predicate the
/// production guard sites depend on. Callers wrap the dict in an array, so mirror that.
private func isSerializable(_ dict: [String: Any]) -> Bool {
    JSONSerialization.isValidJSONObject([dict])
}

// MARK: - FreeAPS (App Group / widget)

@Suite("Payload mappers — FreeAPS")
struct FreeAPSMapperTests {
    @Test("SensorGlucose.toFreeAPS has the expected keys and serializes")
    func sensorGlucose() throws {
        let reading = SensorGlucose(timestamp: Date(timeIntervalSince1970: 1_700_000_000), rawGlucoseValue: 120, intGlucoseValue: 120)
        let mapped = try #require(reading.toFreeAPS())
        #expect(Set(mapped.keys) == ["Value", "Trend", "DT", "direction", "from"])
        #expect(mapped["Value"] as? Int == 120)
        #expect(isSerializable(mapped))
    }

    @Test("BloodGlucose.toFreeAPS has the expected keys and serializes")
    func bloodGlucose() throws {
        let reading = BloodGlucose(timestamp: Date(timeIntervalSince1970: 1_700_000_000), glucoseValue: 95)
        let mapped = try #require(reading.toFreeAPS())
        #expect(Set(mapped.keys) == ["Value", "Trend", "DT", "direction", "from"])
        #expect(mapped["Value"] as? Int == 95)
        #expect(isSerializable(mapped))
    }
}

// MARK: - Nightscout

@Suite("Payload mappers — Nightscout")
struct NightscoutMapperTests {
    @Test("SensorGlucose.toNightscoutGlucose keys + sgv + serializes")
    func sensorGlucose() throws {
        let reading = SensorGlucose(timestamp: Date(timeIntervalSince1970: 1_700_000_000), rawGlucoseValue: 120, intGlucoseValue: 120)
        let mapped = try #require(reading.toNightscoutGlucose())
        #expect(Set(mapped.keys) == ["_id", "device", "date", "dateString", "type", "sgv", "rawbg", "direction", "trend", "glucoseDirect"])
        #expect(mapped["type"] as? String == "sgv")
        #expect(mapped["sgv"] as? Int == 120)
        #expect(isSerializable(mapped))
    }

    @Test("BloodGlucose.toNightscoutGlucose keys + mbg + serializes")
    func bloodGlucose() throws {
        let reading = BloodGlucose(timestamp: Date(timeIntervalSince1970: 1_700_000_000), glucoseValue: 95)
        let mapped = try #require(reading.toNightscoutGlucose())
        #expect(Set(mapped.keys) == ["_id", "device", "date", "dateString", "type", "mbg", "glucoseDirect"])
        #expect(mapped["type"] as? String == "mbg")
        #expect(mapped["mbg"] as? Int == 95)
        #expect(isSerializable(mapped))
    }

    @Test("InsulinDelivery.toNightscoutInsulinDelivery keys + insulin + serializes")
    func insulinDelivery() throws {
        let dose = InsulinDelivery(starts: Date(timeIntervalSince1970: 1_700_000_000), ends: Date(timeIntervalSince1970: 1_700_000_000), units: 4.5, type: .mealBolus)
        let mapped = try #require(dose.toNightscoutInsulinDelivery())
        #expect(Set(mapped.keys) == ["_id", "enteredBy", "created_at", "eventType", "insulin", "glucoseDirect"])
        #expect(mapped["insulin"] as? Double == 4.5)
        #expect(mapped["eventType"] as? String == "Meal Bolus")
        #expect(isSerializable(mapped))
    }

    @Test("Sensor.toNightscoutSensorStart returns a serializable dict with serial + startTimestamp")
    func sensorStart() throws {
        var sensor = makeSensor(serial: "TEST123")
        sensor.startTimestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let mapped = try #require(sensor.toNightscoutSensorStart())
        #expect(Set(mapped.keys) == ["_id", "eventType", "created_at", "enteredBy"])
        #expect(mapped["_id"] as? String == "TEST123")
        #expect(mapped["eventType"] as? String == "Sensor Start")
        #expect(isSerializable(mapped))
    }

    @Test("Sensor.toNightscoutSensorStart is nil without a serial")
    func sensorStartNilSerial() {
        var sensor = makeSensor(serial: nil)
        sensor.startTimestamp = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(sensor.toNightscoutSensorStart() == nil)
    }

    @Test("Sensor.toNightscoutSensorStart is nil without a startTimestamp")
    func sensorStartNilTimestamp() {
        let sensor = makeSensor(serial: "TEST123") // startTimestamp defaults to nil
        #expect(sensor.toNightscoutSensorStart() == nil)
    }

    private func makeSensor(serial: String?) -> Sensor {
        Sensor(family: .libre2, type: .libre2EU, region: .european, serial: serial, state: .ready, age: 100, lifetime: 20160)
    }
}
