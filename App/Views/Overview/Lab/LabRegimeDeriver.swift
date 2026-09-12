//
//  LabRegimeDeriver.swift
//  DOSBTS
//
//  Chart Lab P2 (DMNC-1501). A "regime" is a stretch of day a tagged journal
//  note says was not normal — SICK, STRESSED, SLUGGISH. It is DERIVED from the
//  notes at render time and never stored: there is no regime table, no regime
//  action, and no fourth thing for a user to keep up to date.
//
//  The duration is a default, not a claim. `isOpen` says the user has not told
//  us it ended, which is what the `STILL <TAG>? Y / N` row exists to ask.
//
//  Pure Foundation: no SwiftUI, no store.
//

import Foundation

// MARK: - RegimeBand

struct RegimeBand: Identifiable, Equatable {
    /// The originating note's id — derived, so the note IS the identity.
    let id: String
    let tag: JournalNoteTag
    let start: Date
    let end: Date
    /// No later note closed this band; `end` is still only the default.
    let isOpen: Bool

    /// `STRESSED 15→19`, the prototype's shape: what, and for how long.
    var label: String {
        let calendar = Calendar.current
        let from = calendar.component(.hour, from: start)
        let to = calendar.component(.hour, from: end)
        return "\(tag.localizedDescription) \(from)→\(to)"
    }
}

// MARK: - RegimeDeriver

enum RegimeDeriver {
    // MARK: Defaults (test-pinned)

    /// A note whose text is this closes the standing regime without opening
    /// one — what the `STILL <TAG>?` row's **N** writes.
    static let closeMarkerText = "BACK TO NORMAL"
    /// Stress passes in an afternoon; illness does not.
    static let stressedDuration: TimeInterval = 4 * 60 * 60
    static let sickDuration: TimeInterval = 24 * 60 * 60

    /// How long a tag runs when nothing closes it. `.other` has no duration —
    /// it is a note, not a regime.
    static func defaultEnd(for tag: JournalNoteTag, start: Date, dayEnd: Date) -> Date? {
        switch tag {
        case .sick:
            return start.addingTimeInterval(sickDuration)
        case .stressed:
            return start.addingTimeInterval(stressedDuration)
        case .sluggish:
            // Bad sleep is a property of the day, so it runs out with the day.
            return max(dayEnd, start)
        case .other:
            return nil
        }
    }

    /// Derive the day's bands. `now` is taken rather than read so the result is
    /// render-stable and unit-testable.
    static func derive(notes: [JournalNote], now: Date, dayEnd: Date) -> [RegimeBand] {
        let sorted = notes.sorted { $0.timestamp < $1.timestamp }

        return sorted.enumerated().compactMap { index, note -> RegimeBand? in
            guard
                let tag = note.tag,
                let defaultEnd = defaultEnd(for: tag, start: note.timestamp, dayEnd: dayEnd)
            else { return nil }

            // The next note that says the world changed: any tagged note (it
            // opens its own regime) or an explicit close marker.
            let closer = sorted[(index + 1)...].first { later in
                later.tag != nil || isCloseMarker(later)
            }

            if let closer {
                return RegimeBand(
                    id: note.id.uuidString,
                    tag: tag,
                    start: note.timestamp,
                    // A closer NEVER extends a band — the default is the longest
                    // it can honestly claim — but it always closes it, even when
                    // it lands after the default end. That is the normal case:
                    // `STILL <TAG>?` is asked at the default end, so the answer
                    // arrives after it, and a `< defaultEnd` guard would drop
                    // every answer the user ever gives and ask again forever.
                    end: min(defaultEnd, closer.timestamp),
                    isOpen: false
                )
            }

            return RegimeBand(
                id: note.id.uuidString,
                tag: tag,
                start: note.timestamp,
                end: defaultEnd,
                isOpen: true
            )
        }
    }

    /// Case- and whitespace-insensitive, so a note the user typed by hand reads
    /// the same as the one the **N** button writes.
    static func isCloseMarker(_ note: JournalNote) -> Bool {
        note.text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == closeMarkerText
    }
}

// MARK: - RegimePrompt

/// When to ask `STILL <TAG>? Y / N`.
enum RegimePrompt {
    /// Asked this far before a band's default end — early enough to extend it
    /// before the chart quietly stops saying anything.
    static let leadSeconds: TimeInterval = 30 * 60

    /// The band worth asking about, or nil. Pure so the visibility rule is
    /// pinned by a test rather than by watching a clock.
    static func shouldShow(bands: [RegimeBand], now: Date) -> RegimeBand? {
        bands
            .filter { $0.isOpen && now >= $0.end.addingTimeInterval(-leadSeconds) }
            .max { $0.start < $1.start }
    }
}
