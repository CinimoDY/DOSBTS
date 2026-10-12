//
//  FoodNameSearch.swift
//  DOSBTS
//
//  The ONE place the food-history name filter lives (DMNC-1484, DMNC-1561).
//
//  Contains-match with `localizedCaseInsensitiveContains`, dedupe with
//  `lowercased()` — never SQL `LIKE`/`COLLATE NOCASE`, which fold ASCII only
//  and silently miss or double-count `äpfel`/`Äpfel`
//  (docs/solutions/logic-errors/sqlite-like-folds-ascii-only-non-ascii-search-misses-20260809.md).
//

import Foundation

enum FoodNameSearch {
    /// Candidates whose name contains `needle`, first occurrence per
    /// case-folded name, in input order, at most `limit`. `limit` applies AFTER
    /// filtering so old foods stay reachable.
    static func distinctNameMatches<T>(
        _ candidates: [T],
        needle: String,
        limit: Int,
        name: (T) -> String
    ) -> [T] {
        guard !needle.isEmpty, limit > 0 else { return [] }

        var seen = Set<String>()
        var result: [T] = []

        for candidate in candidates {
            let candidateName = name(candidate)
            guard candidateName.localizedCaseInsensitiveContains(needle),
                  seen.insert(candidateName.lowercased()).inserted else { continue }
            result.append(candidate)
            if result.count == limit { break }
        }

        return result
    }
}
