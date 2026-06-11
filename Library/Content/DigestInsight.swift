//
//  DigestInsight.swift
//  DOSBTS
//
//  Structured daily-digest AI insight. The Claude digest call returns one
//  JSON object matching this shape; it is stored verbatim in the existing
//  DailyDigest.aiInsight string column (no schema migration) and parsed at
//  render time. Insights generated before the structured format — or any
//  response that fails to parse — fall back to the legacy plain-text
//  rendering, so old rows keep working.
//

import Foundation

public struct DigestInsight: Equatable {
    public enum Grade: String {
        case good, mixed, rough
    }

    public enum Tone: String {
        case good, warn, bad
    }

    public struct Fact: Equatable {
        public let label: String
        public let value: String
        public let tone: Tone

        public init(label: String, value: String, tone: Tone) {
            self.label = label
            self.value = value
            self.tone = tone
        }
    }

    public let headline: String
    public let grade: Grade
    public let facts: [Fact]
    public let tips: [String]
    public let cheer: String?

    public init(headline: String, grade: Grade, facts: [Fact], tips: [String], cheer: String?) {
        self.headline = headline
        self.grade = grade
        self.facts = facts
        self.tips = tips
        self.cheer = cheer
    }

    /// Lenient parse: tolerates code fences or stray prose around the JSON
    /// object, unknown grade/tone strings (mapped to safe defaults), and
    /// missing optional fields. Returns nil only when there is no usable
    /// JSON object with a headline — the caller then renders the raw text.
    public static func parse(_ raw: String) -> DigestInsight? {
        guard let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}"),
              start < end,
              let data = String(raw[start...end]).data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let headline = object["headline"] as? String,
              !headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        let grade = (object["grade"] as? String).flatMap(Grade.init(rawValue:)) ?? .mixed

        let facts: [Fact] = ((object["facts"] as? [[String: Any]]) ?? []).compactMap { dict in
            guard let label = dict["label"] as? String,
                  let value = dict["value"] as? String else { return nil }
            let tone = (dict["tone"] as? String).flatMap(Tone.init(rawValue:)) ?? .warn
            return Fact(label: label, value: value, tone: tone)
        }

        let tips = ((object["tips"] as? [String]) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let cheer = (object["cheer"] as? String)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }

        return DigestInsight(
            headline: headline.trimmingCharacters(in: .whitespacesAndNewlines),
            grade: grade,
            facts: Array(facts.prefix(3)),
            tips: Array(tips.prefix(2)),
            cheer: cheer
        )
    }
}
