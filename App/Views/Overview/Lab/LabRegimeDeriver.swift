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

    /// Derive the day's bands. Deliberately clock-free: a band's extent is a
    /// property of the NOTES, so the result is render-stable and unit-testable.
    /// Whether a band is worth asking about is `RegimePrompt`'s job.
    static func derive(notes: [JournalNote], dayEnd: Date) -> [RegimeBand] {
        let sorted = notes.sorted { $0.timestamp < $1.timestamp }

        return sorted.enumerated().compactMap { index, note -> RegimeBand? in
            guard
                let tag = note.tag,
                let defaultEnd = defaultEnd(for: tag, start: note.timestamp, dayEnd: dayEnd)
            else { return nil }

            // The next note that says the world changed: one that OPENS its own
            // regime, or an explicit close marker. A tag that opens nothing
            // (`.other`) is just a note — "took paracetamol" must not end SICK.
            let closer = sorted[(index + 1)...].first { later in
                isCloseMarker(later) || opensARegime(later, dayEnd: dayEnd)
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

    /// True when this note would open a band of its own — which is what makes it
    /// able to end the one before it. `.other` and untagged notes do not.
    static func opensARegime(_ note: JournalNote, dayEnd: Date) -> Bool {
        guard let tag = note.tag else { return false }
        return defaultEnd(for: tag, start: note.timestamp, dayEnd: dayEnd) != nil
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

    /// The band worth asking about, or nil.
    ///
    /// `isLiveDay` is load-bearing, not decoration. `journalNoteValues` is
    /// scoped to the selected day, so on a PAST day the answer would be written
    /// at `now` (today), land outside the day being shown, never come back as a
    /// closer — and the row would ask again forever, inserting an orphan
    /// `BACK TO NORMAL` into the log on every tap. A day you are only reading
    /// is not a day you can answer for.
    static func shouldShow(bands: [RegimeBand], now: Date, isLiveDay: Bool) -> RegimeBand? {
        guard isLiveDay else { return nil }

        return bands
            .filter { $0.isOpen && now >= $0.end.addingTimeInterval(-leadSeconds) }
            .max { $0.start < $1.start }
    }
}
