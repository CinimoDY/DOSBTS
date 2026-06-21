//
//  ChangelogParserTests.swift
//  DOSBTSTests
//
//  U1 (DMNC-1147): the pure changelog parser. Pins build/group structure,
//  the KTD2 trailing-metadata grammar across the real corpus shapes (R3),
//  the {tour:} destination marker (R10/R12/AE4), [Unreleased] exclusion, and
//  lenient degradation on malformed input.
//

import Foundation
import Testing
@testable import DOSBTSApp

@Suite("Changelog parser (DMNC-1147)")
struct ChangelogParserTests {

    // MARK: Structure

    @Test("Two builds parse newest-first with correct numbers and dates")
    func twoBuilds() {
        let md = """
        ## [Build 106] — 2026-06-20

        ### Added
        - Thing one

        ## [Build 105] — 2026-06-18

        ### Changed
        - Thing two
        """
        let builds = ChangelogParser.parse(md)
        #expect(builds.count == 2)
        #expect(builds[0].buildNumber == 106)
        #expect(builds[0].displayName == "106")
        #expect(builds[0].date == "2026-06-20")
        #expect(builds[1].buildNumber == 105)
        #expect(builds[1].date == "2026-06-18")
    }

    @Test("Entries land under the right group; absent groups are omitted, not empty")
    func groupRouting() {
        let md = """
        ## [Build 10] — 2026-01-01

        ### Added
        - Added thing

        ### Fixed
        - Fixed thing
        """
        let builds = ChangelogParser.parse(md)
        #expect(builds.count == 1)
        let groups = builds[0].sections.map(\.group)
        #expect(groups == [.added, .fixed])
        #expect(builds[0].sections.first?.entries.first?.text == "Added thing")
        // Changed / Removed are absent — not present as empty sections.
        #expect(!groups.contains(.changed))
        #expect(!groups.contains(.removed))
    }

    // MARK: Metadata stripping (R3, KTD2)

    @Test("Trailing developer metadata is stripped across the real corpus shapes")
    func stripsTrailingMetadata() {
        #expect(firstEntry("- Pulsing dots loading indicator — DMNC-797") == "Pulsing dots loading indicator")
        #expect(firstEntry("- Correction bolus cue — DMNC-715, PR #62") == "Correction bolus cue")
        #expect(firstEntry("- Infographic digest — PR #54.") == "Infographic digest")
        #expect(firstEntry("- Y-axis flush with edge — DMNC-1045 follow-up") == "Y-axis flush with edge")
        #expect(firstEntry("- Siri logging — DMNC-633, DMNC-634.") == "Siri logging")
    }

    @Test("Chained '— A — B' metadata runs are all stripped (lines 70/75 in the corpus)")
    func stripsChainedMetadata() {
        #expect(firstEntry("- Shared meal row component (deleting required edit mode) — R3, R4, AE4 — PR #52.")
            == "Shared meal row component (deleting required edit mode)")
        #expect(firstEntry("- ASK AI navigates on first tap — DMNC-1023 wave (R6) — PR #52.")
            == "ASK AI navigates on first tap")
    }

    @Test("An embedded prose em-dash is preserved; only the trailing ref run is stripped")
    func preservesProseEmDash() {
        let text = firstEntry("- A toast lights up — the app's first positive feedback — DMNC-772, PR #59.")
        #expect(text == "A toast lights up — the app's first positive feedback")
    }

    @Test("A trailing em-dash segment without a known leading token is left intact")
    func keepsNonMetadataTail() {
        // The bold-term-then-description shape (e.g. Build 51/53) must survive.
        let text = firstEntry("- Predictive low alarm — 20-min forward extrapolation of trajectory")
        #expect(text == "Predictive low alarm — 20-min forward extrapolation of trajectory")
    }

    // MARK: Destination marker (R10, R12, AE4)

    @Test("A {tour:} marker yields a destinationKey and strips the token from display text")
    func extractsTourMarker() {
        let entry = firstChangelogEntry("- Day/night alarm profiles {tour:settings/alarms} — DMNC-692")
        #expect(entry?.destinationKey == "settings/alarms")
        #expect(entry?.text == "Day/night alarm profiles")
    }

    @Test("An entry without a marker — including a fix — has a nil destinationKey (AE4)")
    func noMarkerIsNil() {
        let entry = firstChangelogEntry("- Chart y-axis now flush with the edge — DMNC-1045 follow-up")
        #expect(entry?.destinationKey == nil)
        #expect(entry?.text == "Chart y-axis now flush with the edge")
    }

    // MARK: Exclusions & leniency

    @Test("[Unreleased] content is excluded from output")
    func excludesUnreleased() {
        let md = """
        ## [Unreleased]

        ### Added
        - Not shipped yet

        ## [Build 106] — 2026-06-20

        ### Added
        - Shipped
        """
        let builds = ChangelogParser.parse(md)
        #expect(builds.count == 1)
        #expect(builds[0].buildNumber == 106)
        #expect(builds[0].sections.first?.entries.first?.text == "Shipped")
    }

    @Test("Empty and malformed input degrade to [] without crashing")
    func lenientDegradation() {
        #expect(ChangelogParser.parse("").isEmpty)
        #expect(ChangelogParser.parse("\n\n   \n").isEmpty)
        #expect(ChangelogParser.parse("# Changelog\n\nJust some intro prose.").isEmpty)
        // A build header with no parseable number is skipped, not crashed.
        #expect(ChangelogParser.parse("## [Build] — 2026-01-01\n\n### Added\n- x").isEmpty)
    }

    @Test("A range header keeps its label for display and sorts by its first number")
    func rangeHeader() {
        let builds = ChangelogParser.parse("## [Build 35–48] — 2026-04-08 → 2026-04-15\n\n### Changed\n- Layout overhaul")
        #expect(builds.count == 1)
        #expect(builds[0].buildNumber == 35)
        #expect(builds[0].displayName == "35–48")
    }

    @Test("Multi-line entries fold sub-bullets into the parent entry text")
    func multiLineEntry() {
        let md = """
        ## [Build 73] — 2026-04-25

        ### Changed
        - Marker batches show one icon per type:
          - 1 meal → bare apple icon
          - 2+ meals → apple icon + green border
        """
        let builds = ChangelogParser.parse(md)
        let text = builds.first?.sections.first?.entries.first?.text ?? ""
        #expect(text.hasPrefix("Marker batches show one icon per type:"))
        #expect(text.contains("1 meal"))
        #expect(text.contains("2+ meals"))
    }

    // MARK: Bundled resource (U2)

    @Test("bundled() reads and parses the committed Library/Resources/CHANGELOG.md")
    func bundledReturnsBuilds() {
        // FrameworkBundle.main resolves to the app bundle (Library compiles into
        // the app target), which ships Library/Resources/CHANGELOG.md.
        let builds = ChangelogParser.bundled()
        #expect(!builds.isEmpty)
        // Newest-first, with a parseable build number.
        #expect(builds.first?.buildNumber ?? 0 > 0)
    }

    @Test("A missing/unreadable resource degrades to [] (same path as empty input)")
    func bundledMissingResourceIsEmpty() {
        // bundled() returns parse(contents) and parse("") -> [], so the nil-URL /
        // unreadable-file guard yields [] rather than crashing (R2 leniency).
        #expect(ChangelogParser.parse("").isEmpty)
    }

    // MARK: Helpers

    private func firstEntry(_ line: String) -> String {
        firstChangelogEntry(line)?.text ?? ""
    }

    private func firstChangelogEntry(_ line: String) -> ChangelogEntry? {
        let md = "## [Build 1] — 2026-01-01\n\n### Added\n\(line)"
        return ChangelogParser.parse(md).first?.sections.first?.entries.first
    }
}
