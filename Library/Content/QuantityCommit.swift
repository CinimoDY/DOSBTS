//
//  QuantityCommit.swift
//  DOSBTS
//
//  Pure model for the "hold a favourite/recent a second time to set a
//  count" flow (DMNC-1562). The first hold logs one entry as always; a
//  second hold on the same source inside `rearmWindow` opens a count
//  session, and ADD rewrites that single entry as `N× name` with its
//  macros multiplied. No new entry is ever minted for the extra units.
//

import Foundation

struct QuantityCommitSession {
    let sourceKey: String
    let entryID: UUID
    let baseEntry: MealEntry
    let fromFavorite: Bool
    var count: Int
}

enum QuantityCommit {
    /// A second hold on the same source counts only this long after the first log.
    static let rearmWindow: TimeInterval = 15
    /// Count mode closes itself after this long without interaction.
    static let idleTimeout: TimeInterval = 20
    static let countRange = 2...99

    static func sourceKey(for description: String) -> String {
        description.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// True when the description already carries an `N× ` prefix, i.e. it is
    /// the output of `scaled` and must never be used as a base.
    static func isScaledDescription(_ description: String) -> Bool {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: #"^\d+× "#, options: .regularExpression) != nil
    }

    /// Governs ENTERING count mode only; holds while the stepper is open
    /// always increment. Refuses scaled sources and hypo-treatment sources.
    static func shouldEnterCountMode(
        lastLogged: (sourceKey: String, entryID: UUID, at: Date)?,
        tappedSourceKey: String,
        now: Date,
        hypoSourceKeys: Set<String> = []
    ) -> Bool {
        guard let lastLogged, lastLogged.sourceKey == tappedSourceKey else { return false }
        guard !isScaledDescription(tappedSourceKey), !hypoSourceKeys.contains(tappedSourceKey) else { return false }
        return now.timeIntervalSince(lastLogged.at) < rearmWindow
    }

    static func clamped(_ count: Int) -> Int {
        min(max(count, countRange.lowerBound), countRange.upperBound)
    }

    static func scaled(_ base: MealEntry, count: Int) -> MealEntry {
        let n = clamped(count)
        let factor = Double(n)
        return MealEntry(
            id: base.id,
            timestamp: base.timestamp,
            mealDescription: "\(n)× \(base.mealDescription)",
            carbsGrams: base.carbsGrams.map { $0 * factor },
            proteinGrams: base.proteinGrams.map { $0 * factor },
            fatGrams: base.fatGrams.map { $0 * factor },
            calories: base.calories.map { $0 * factor },
            fiberGrams: base.fiberGrams.map { $0 * factor },
            analysisSessionId: base.analysisSessionId
        )
    }
}
