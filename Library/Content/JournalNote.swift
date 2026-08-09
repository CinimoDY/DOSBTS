//
//  JournalNote.swift
//  DOSBTS
//

import Foundation

// MARK: - JournalNoteTag

/// Fixed V1 tag set. The free text carries the detail; the tag exists so the
/// digest prompt (and, later, a filter) can group notes without parsing prose.
enum JournalNoteTag: String, Codable, CaseIterable, Identifiable {
    case sick
    case stressed
    case sluggish
    case other

    // MARK: Internal

    var id: String { rawValue }

    /// Uppercase DOS-style display label (chips, list rows, prompt tags).
    var localizedDescription: String {
        switch self {
        case .sick:
            return LocalizedString("SICK")
        case .stressed:
            return LocalizedString("STRESSED")
        case .sluggish:
            return LocalizedString("SLUGGISH")
        case .other:
            return LocalizedString("OTHER")
        }
    }
}

// MARK: - JournalNote

/// A timestamped free-text note with one optional tag — the context glucose
/// numbers can't show ("family's sick", "slept badly"). V1 is add + delete
/// only; there is no edit path.
struct JournalNote: CustomStringConvertible, Codable, Identifiable, Equatable {
    // MARK: Lifecycle

    init(timestamp: Date, text: String, tag: JournalNoteTag? = nil) {
        self.init(id: UUID(), timestamp: timestamp, text: text, tag: tag)
    }

    init(id: UUID, timestamp: Date, text: String, tag: JournalNoteTag? = nil) {
        self.id = id
        self.timestamp = timestamp.toRounded(on: 1, .minute)
        // Clamped here rather than only at the entry form so no call site can
        // store an unbounded blob — the text ends up in an AI prompt.
        self.text = JournalNote.clamp(text)
        self.tag = tag
    }

    // MARK: Internal

    /// Hard cap on stored note text.
    static let maxTextLength = 500

    let id: UUID
    let timestamp: Date
    let text: String
    let tag: JournalNoteTag?

    var description: String {
        "{ id: \(id), timestamp: \(timestamp.toLocalTime()), tag: \(tag?.rawValue ?? "none"), chars: \(text.count) }"
    }

    /// Trim, then clamp to `maxTextLength`. Pure so the rule is unit-testable
    /// and shared between the entry form's validation and the model's init.
    static func clamp(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxTextLength))
    }
}
