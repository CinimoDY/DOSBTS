import Foundation
import Testing

// Source-scan guards that make design-system drift fail `Cmd+U` (DMNC-1222).
//
// These do NOT compile against app symbols — they read the Swift sources straight
// off disk and grep for banned patterns. That keeps the guards honest about what
// literally ships in the tree (previews included) rather than what a linked symbol
// resolves to. Each rule is documented in docs/design-system.md → "Enforcement";
// to relax one, extend its `exempt` set there and here in lockstep.
//
// Scanning is line-oriented on purpose (simple, fast, good failure messages). Two
// known consequences, accepted for now: a banned construct split across a newline
// is not seen, and a banned token sitting in a *trailing* comment or a string
// literal is still matched (whole-line `//` comments are skipped — see
// `isCommentLine`). If a legitimate future line trips a rule that way, prefer
// rewriting the line over loosening the guard.
@Suite("Design-system source guards")
struct StyleGuardTests {
    // #filePath → .../DOSBTSTests/StyleGuardTests.swift → repo root two levels up.
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// The three shipped source roots. Rules that guard "the whole app" scan all three.
    static let standardScope = ["App", "Library", "Widgets"]

    struct Rule {
        /// NSRegularExpression source. Multi-clause rules combine with top-level `|`.
        let pattern: String
        /// Repo-relative directory roots to scan (recursively, `.swift` only).
        let dirs: [String]
        /// Repo-relative paths allowed to match. A trailing `/` marks a directory
        /// prefix (whole subtree exempt); otherwise it is an exact file path.
        var exempt: Set<String> = []
    }

    struct Hit {
        let file: String   // repo-relative
        let line: Int      // 1-based
        let text: String   // trimmed line
    }

    // MARK: - Scanning

    static func swiftFiles(in dir: String) -> [URL] {
        let root = repoRoot.appendingPathComponent(dir)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil
        ) else { return [] }

        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append(url)
        }
        return files
    }

    static func relativePath(of url: URL) -> String {
        let base = repoRoot.path.hasSuffix("/") ? repoRoot.path : repoRoot.path + "/"
        let path = url.path
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path
    }

    static func isExempt(_ relativePath: String, rule: Rule) -> Bool {
        for entry in rule.exempt {
            if entry.hasSuffix("/") {
                if relativePath.hasPrefix(entry) { return true }
            } else if relativePath == entry {
                return true
            }
        }
        return false
    }

    /// A line whose first non-whitespace characters are `//` — a pure single-line
    /// comment (doc `///` included). Commented text is dead, not a live style
    /// violation, so it never counts as a hit. This is what lets a doc comment
    /// literally mention `ProgressView()` without tripping Rule 6.
    static func isCommentLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
    }

    /// Throws — rather than silently returning `[]` — on a malformed pattern or an
    /// unreadable/non-UTF-8 source file. A silent empty result would make the
    /// owning rule pass vacuously; a thrown error fails its `@Test` loudly instead.
    static func scan(_ rule: Rule) throws -> [Hit] {
        let regex = try NSRegularExpression(pattern: rule.pattern)

        var hits: [Hit] = []
        for dir in rule.dirs {
            for url in swiftFiles(in: dir) {
                let relative = relativePath(of: url)
                if isExempt(relative, rule: rule) { continue }
                let contents = try String(contentsOf: url, encoding: .utf8)

                for (index, line) in contents.components(separatedBy: "\n").enumerated() {
                    if isCommentLine(line) { continue }
                    let range = NSRange(line.startIndex..<line.endIndex, in: line)
                    if regex.firstMatch(in: line, range: range) != nil {
                        hits.append(Hit(
                            file: relative,
                            line: index + 1,
                            text: line.trimmingCharacters(in: .whitespaces)
                        ))
                    }
                }
            }
        }
        return hits
    }

    /// "App/Views/Foo.swift:42: <line>" per hit, one per line.
    static func report(_ hits: [Hit]) -> String {
        hits.map { "\($0.file):\($0.line): \($0.text)" }.joined(separator: "\n")
    }

    // MARK: - Sanity

    // Guards against a misresolved `repoRoot` OR a single renamed source root: each
    // root is checked individually, because a rule scanning an empty directory
    // passes vacuously and the aggregate count alone can't tell one dropped root
    // from a smaller tree.
    @Test("repoRoot resolves — every scanned root is reachable and non-empty")
    func repoRootResolves() {
        for dir in Self.standardScope + ["App/Views"] {
            let count = Self.swiftFiles(in: dir).count
            #expect(
                count > 0,
                "\(dir) resolved to 0 .swift files — repoRoot is misresolved or the root was renamed, so every rule scoped to \(dir) would pass vacuously."
            )
        }
        let total = Self.standardScope.reduce(0) { $0 + Self.swiftFiles(in: $1).count }
        #expect(total > 100, "Only \(total) .swift files scanned under \(Self.standardScope) — repoRoot is likely misresolved.")
    }

    // MARK: - Rules

    @Test("Rule 1 — no .font(.system(...)); use DOSTypography")
    func rule1_noSystemFont() throws {
        // Matches both `.font(.system(` and `.font(Font.system(`; a bare `Font.system(`
        // (how the DOSTypography token defs spell it) has no `.font(` prefix, so it passes.
        let hits = try Self.scan(Rule(pattern: #"\.font\((\.|Font\.)system\("#, dirs: Self.standardScope))
        #expect(hits.isEmpty, "Replace .font(.system(...)) with a DOSTypography role:\n\(Self.report(hits))")
    }

    @Test("Rule 2 — no system Font.Dynamic styles; use DOSTypography")
    func rule2_noSemanticSystemFont() throws {
        let rule = Rule(
            pattern: #"\.font\(\.(largeTitle|title2?3?|headline|subheadline|body|callout|footnote|caption2?)\b"#,
            dirs: Self.standardScope
        )
        let hits = try Self.scan(rule)
        #expect(hits.isEmpty, "Replace system Dynamic Type styles (.body/.caption/...) with a DOSTypography role:\n\(Self.report(hits))")
    }

    @Test("Rule 3 — no Color.black / (.black) fills; use inkOnAmber or dosBlack")
    func rule3_noRawBlack() throws {
        // `\.black\b` (not `\.black\)`) so a `.black.opacity(...)` chain is still caught.
        let rule = Rule(
            pattern: #"Color\.black\b|(foregroundStyle|foregroundColor|fill|background)\(\.black\b"#,
            dirs: Self.standardScope
        )
        let hits = try Self.scan(rule)
        #expect(hits.isEmpty, "Use AmberTheme.inkOnAmber (ink on amber) or AmberTheme.dosBlack instead of raw black:\n\(Self.report(hits))")
    }

    @Test("Rule 4 — no .foregroundColor(); use .foregroundStyle()")
    func rule4_noForegroundColor() throws {
        let hits = try Self.scan(Rule(pattern: #"\.foregroundColor\("#, dirs: Self.standardScope))
        #expect(hits.isEmpty, "Migrate .foregroundColor(...) to .foregroundStyle(...):\n\(Self.report(hits))")
    }

    @Test("Rule 5 — no rounded corners; DOS aesthetic is sharp")
    func rule5_noCornerRadius() throws {
        let rule = Rule(
            pattern: #"cornerRadius: *[1-9]|\.cornerRadius\("#,
            dirs: Self.standardScope
        )
        let hits = try Self.scan(rule)
        #expect(hits.isEmpty, "Sharp corners only — drop cornerRadius:\n\(Self.report(hits))")
    }

    @Test("Rule 6 — no indeterminate ProgressView(); use FiguresLoadingView")
    func rule6_noProgressView() throws {
        // Intentionally the empty-parens `ProgressView()` — the indeterminate spinner that
        // FiguresLoadingView replaces. Determinate `ProgressView(value:total:)` gauges
        // (e.g. SensorDetailView's sensor-life / battery bars) are legitimate and have no
        // DOS equivalent, so they are deliberately NOT matched. Scoped to App/Views because
        // that is where the spinner-vs-FiguresLoadingView choice lives.
        let hits = try Self.scan(Rule(pattern: #"ProgressView\(\)"#, dirs: ["App/Views"]))
        #expect(hits.isEmpty, "Use FiguresLoadingView (or .inline) instead of a system ProgressView():\n\(Self.report(hits))")
    }

    @Test("Rule 7 — no inline animation curves; use AnimationTokens")
    func rule7_noInlineAnimationCurves() throws {
        let rule = Rule(
            pattern: #"\.(easeIn|easeOut|easeInOut|linear)\(duration:|spring\(response:"#,
            dirs: Self.standardScope,
            exempt: ["Library/DesignSystem/"]
        )
        let hits = try Self.scan(rule)
        #expect(hits.isEmpty, "Reference an AnimationTokens value instead of an inline curve:\n\(Self.report(hits))")
    }

    @Test("Rule 8 — no raw Color(red:) outside AmberTheme; zero-hex win locked")
    func rule8_noRawColorLiterals() throws {
        // Catches the component initializers — `Color(red:`, `Color(.sRGB, red:`,
        // `Color(white:`, `Color(hue:`, and `UIColor(red:` — not asset/system `Color(...)`.
        let rule = Rule(
            pattern: #"(UI)?Color\((\.\w+, *)?(red|white|hue):"#,
            dirs: Self.standardScope,
            exempt: ["Library/DesignSystem/AmberTheme.swift"]
        )
        let hits = try Self.scan(rule)
        #expect(hits.isEmpty, "All raw color literals live in AmberTheme.swift — add a token there:\n\(Self.report(hits))")
    }
}
