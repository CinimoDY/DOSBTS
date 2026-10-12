//
//  SpeechContextPhrases.swift
//  DOSBTS
//
//  Recognition-bias phrases for `DictationControl.contextualStrings`
//  (DMNC-1486 D5/R3, DMNC-1561).
//
//  `SFSpeechRecognizer.contextualStrings` takes ~100 short phrases, so the
//  caller passes its sources in priority order and this trims, drops blanks,
//  dedupes with `lowercased()` (which folds non-ASCII — the SQL `NOCASE` trap
//  applies to case folding generally) and caps.
//

import Foundation

enum SpeechContextPhrases {
    static func make(_ sources: [String], cap: Int = 100) -> [String] {
        guard cap > 0 else { return [] }

        var seen = Set<String>()
        var phrases: [String] = []
        for candidate in sources {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            phrases.append(trimmed)
            if phrases.count == cap { break }
        }
        return phrases
    }
}
