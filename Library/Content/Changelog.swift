//
//  Changelog.swift
//  DOSBTS
//
//  Always-on changelog (DMNC-1147). Parses the user-facing `CHANGELOG.md`
//  (Keep a Changelog format) into structured builds for the in-app "What's
//  New" surface. `CHANGELOG.md` stays the single authored source (R1); this
//  is the one Swift reader (KTD2) — the deploy path reproduces the same
//  cleaning rules in shell for one build block.
//
//  Cleaning mirrors DigestInsight.parse leniency: malformed lines degrade to
//  plain entries and never crash. Developer metadata (`— DMNC-NNN, PR #NN`
//  and the multi-issue / trailing-word / period variants) is stripped from
//  the tail (R3); the optional `{tour:<key>}` destination marker (KTD3) is
//  extracted and stripped (R10); entries without a marker render plain (R12).
//

import Foundation

// MARK: - Models

/// One changelog line: cleaned display text plus an optional deep-link key.
public struct ChangelogEntry: Equatable {
    /// User-facing text — developer metadata and the `{tour:}` token removed.
    public let text: String
    /// Closed-set destination key from a `{tour:<key>}` marker, else nil (R12).
    public let destinationKey: String?

    public init(text: String, destinationKey: String?) {
        self.text = text
        self.destinationKey = destinationKey
    }
}

/// A `### Added / Changed / Fixed / Removed` group within a build (R3).
public struct ChangelogSection: Equatable {
    public enum Group: String, CaseIterable {
        case added = "Added"
        case changed = "Changed"
        case fixed = "Fixed"
        case removed = "Removed"
    }

    public let group: Group
    public let entries: [ChangelogEntry]

    public init(group: Group, entries: [ChangelogEntry]) {
        self.group = group
        self.entries = entries
    }
}

/// One `## [Build N] — YYYY-MM-DD` block. `buildNumber` is the numeric sort /
/// dedup / `lastSeenBuild` comparison key; `displayName` preserves the
/// authored label (e.g. `106`, or a range like `35–48` for the deep history).
public struct ChangelogBuild: Equatable, Identifiable {
    public let buildNumber: Int
    public let displayName: String
    public let date: String
    public let sections: [ChangelogSection]

    public var id: Int { buildNumber }

    public init(buildNumber: Int, displayName: String, date: String, sections: [ChangelogSection]) {
        self.buildNumber = buildNumber
        self.displayName = displayName
        self.date = date
        self.sections = sections
    }
}

// MARK: - ChangelogParser

public enum ChangelogParser {
    /// Parse Keep-a-Changelog markdown into builds, newest-first (file order).
    /// `[Unreleased]` and any non-`[Build N]` headers (intro, Pre-fork) are
    /// excluded. Never throws; unparseable input returns `[]`.
    public static func parse(_ markdown: String) -> [ChangelogBuild] {
        var builds: [ChangelogBuild] = []

        // Accumulators for the build currently being read.
        var buildNumber: Int?
        var displayName = ""
        var date = ""
        var sections: [ChangelogSection] = []

        // Current group + its accumulated entries.
        var groupName: ChangelogSection.Group?
        var groupEntries: [ChangelogEntry] = []

        // Current (possibly multi-line) entry's raw text.
        var entryRaw: String?

        func flushEntry() {
            defer { entryRaw = nil }
            guard let raw = entryRaw,
                  !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            groupEntries.append(makeEntry(raw))
        }

        func flushGroup() {
            flushEntry()
            if let groupName, !groupEntries.isEmpty {
                sections.append(ChangelogSection(group: groupName, entries: groupEntries))
            }
            groupName = nil
            groupEntries = []
        }

        func flushBuild() {
            flushGroup()
            if let buildNumber {
                builds.append(ChangelogBuild(
                    buildNumber: buildNumber,
                    displayName: displayName,
                    date: date,
                    sections: sections
                ))
            }
            buildNumber = nil
            displayName = ""
            date = ""
            sections = []
        }

        for line in markdown.components(separatedBy: "\n") {
            if line.hasPrefix("### ") {
                flushGroup()
                let name = line.dropFirst(4).trimmingCharacters(in: .whitespaces)
                groupName = ChangelogSection.Group(rawValue: name)
                continue
            }

            if line.hasPrefix("## ") {
                // A new top-level header closes the previous build.
                flushBuild()
                if let header = parseBuildHeader(line) {
                    buildNumber = header.number
                    displayName = header.displayName
                    date = header.date
                }
                // Non-build headers ([Unreleased], Pre-fork) leave buildNumber
                // nil, so their entries are ignored below.
                continue
            }

            // Only accumulate inside a recognized build + group.
            guard buildNumber != nil, groupName != nil else { continue }

            if line.hasPrefix("- ") {
                flushEntry()
                entryRaw = String(line.dropFirst(2))
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushEntry()
            } else if entryRaw != nil {
                // Sub-bullet or wrapped continuation of the current entry.
                entryRaw?.append("\n" + trimmed)
            }
        }

        flushBuild()
        return builds
    }

    // MARK: Entry cleaning

    private static func makeEntry(_ raw: String) -> ChangelogEntry {
        var text = raw

        // 1. Extract the optional destination marker (KTD3, R10).
        var destinationKey: String?
        if let token = extractTourToken(in: text) {
            destinationKey = token.key
            text = token.stripped
        }

        // 2. Strip trailing developer-metadata runs (R3, KTD2).
        text = stripTrailingMetadata(text)

        return ChangelogEntry(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            destinationKey: destinationKey
        )
    }

    /// Pull the first `{tour:<key>}` token out of `text`, returning the key and
    /// the text with the token removed. Nil when no marker is present (R12).
    private static func extractTourToken(in text: String) -> (key: String, stripped: String)? {
        guard let regex = tourTokenRegex,
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ),
            let fullRange = Range(match.range, in: text),
            let keyRange = Range(match.range(at: 1), in: text) else { return nil }

        let key = String(text[keyRange]).trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }

        var stripped = text
        stripped.replaceSubrange(fullRange, with: "")
        // Collapse the double space the removal can leave behind.
        stripped = stripped.replacingOccurrences(of: "  ", with: " ")
        return (key, stripped)
    }

    /// Remove one or more trailing `— <issue refs>` runs (KTD2). Each run, after
    /// the last ` — `, must begin with a known issue token and contain only
    /// issue-shaped content; a prose em-dash segment (lowercase sentence) stops
    /// the strip, so embedded em-dashes are preserved.
    private static func stripTrailingMetadata(_ input: String) -> String {
        var text = input
        let separator = " \u{2014} " // space, em dash, space

        // Bounded — each pass removes a suffix, so the loop terminates; the cap
        // is defensive only.
        for _ in 0 ..< 8 {
            guard let range = text.range(of: separator, options: .backwards) else { break }
            let tail = String(text[range.upperBound...])
            guard isMetadataRun(tail) else { break }
            text = String(text[..<range.lowerBound])
        }
        return text
    }

    private static func isMetadataRun(_ tail: String) -> Bool {
        guard let regex = metadataRegex else { return false }
        let range = NSRange(tail.startIndex..., in: tail)
        return regex.firstMatch(in: tail, range: range) != nil
    }

    // MARK: Header parsing

    private static func parseBuildHeader(_ line: String) -> (number: Int, displayName: String, date: String)? {
        guard let open = line.firstIndex(of: "["),
              let close = line.firstIndex(of: "]"),
              open < close else { return nil }

        let inner = String(line[line.index(after: open)..<close]) // e.g. "Build 106"
        guard inner.lowercased().hasPrefix("build") else { return nil } // skip [Unreleased]
        guard let number = firstInteger(in: inner) else { return nil }

        // displayName: drop the leading "Build " word, keep the rest verbatim
        // (so a range header reads "35–48", not "35").
        var displayName = inner
        if let space = inner.firstIndex(of: " ") {
            displayName = String(inner[inner.index(after: space)...])
        }
        displayName = displayName.trimmingCharacters(in: .whitespaces)

        var date = ""
        if let sep = line.range(of: " \u{2014} ") {
            date = String(line[sep.upperBound...]).trimmingCharacters(in: .whitespaces)
        }

        return (number, displayName, date)
    }

    private static func firstInteger(in string: String) -> Int? {
        var digits = ""
        for character in string {
            if character.isNumber {
                digits.append(character)
            } else if !digits.isEmpty {
                break
            }
        }
        return Int(digits)
    }

    // MARK: Compiled patterns

    /// `{tour:<key>}` — captures the key.
    private static let tourTokenRegex = makeRegex("\\{tour:\\s*([^}]+?)\\s*\\}")

    /// A full trailing-metadata run: a leading known issue token, then any mix
    /// of further tokens / short lowercase connectors (e.g. "follow-up",
    /// "wave") / parenthesized ref groups, and an optional trailing period.
    private static let metadataRegex: NSRegularExpression? = {
        let token = "(?:DMNC-\\d+|PR #\\d+|R\\d+|AE\\d+|D\\d+|[A-Z]{2,}-\\d+)"
        let extra = "(?:" + token + "|[a-z][a-z-]+|\\([^)]*\\))"
        return makeRegex("^" + token + "(?:,?\\s+" + extra + ")*\\.?$")
    }()

    /// Patterns are static literals — a compile failure surfaces in tests, not
    /// at runtime. A nil result degrades to "no strip", never a crash.
    private static func makeRegex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern)
    }
}

// MARK: - Bundled read (R2)

public extension ChangelogParser {
    /// Parse the changelog copy committed into the app bundle
    /// (`Library/Resources/CHANGELOG.md`). `deploy.sh` refreshes that copy
    /// before archiving (U7), so every TestFlight build carries the changelog
    /// it ships. Returns `[]` if the resource is missing or unreadable — the
    /// What's New surface then shows its empty state rather than crashing.
    static func bundled() -> [ChangelogBuild] {
        guard let url = FrameworkBundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let markdown = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return parse(markdown)
    }
}
