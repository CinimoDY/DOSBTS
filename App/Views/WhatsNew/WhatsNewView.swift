//
//  WhatsNewView.swift
//  DOSBTS
//
//  In-app "What's New" patch-notes artifact (DMNC-1147, R8/R9). Renders the
//  changelog builds as DOS patch-notes cards with a `PATCH NOTES · BUILD N`
//  banner, color-coded section labels, and the digest's staged phosphor reveal
//  (static under Reduce Motion). Used in two places:
//   - the auto-sheet (linksActive: true) — entries with a {tour:} marker are
//     tappable and call back with a ChangelogDestination; capped to the first
//     few builds with a SHOW ALL expansion (KTD11);
//   - the Settings → About history (linksActive: false) — full history, plain
//     non-interactive entries (R12).
//

import SwiftUI

struct WhatsNewView: View {
    /// Builds shown initially — the capped slice for the auto-sheet, or the
    /// full history for the About entry.
    let builds: [ChangelogBuild]
    /// The full set the `SHOW ALL` row expands to (auto-sheet). Equal to
    /// `builds` when there is nothing more to show.
    let allBuilds: [ChangelogBuild]
    /// Linked entries are tappable only in the auto-sheet.
    let linksActive: Bool
    /// Fired when a linked entry is tapped (auto-sheet dismiss-then-navigate).
    var onSelectDestination: (ChangelogDestination) -> Void = { _ in }

    @State private var expanded = false

    init(
        builds: [ChangelogBuild],
        allBuilds: [ChangelogBuild]? = nil,
        linksActive: Bool,
        onSelectDestination: @escaping (ChangelogDestination) -> Void = { _ in }
    ) {
        self.builds = builds
        self.allBuilds = allBuilds ?? builds
        self.linksActive = linksActive
        self.onSelectDestination = onSelectDestination
    }

    private var shownBuilds: [ChangelogBuild] {
        expanded ? allBuilds : builds
    }

    private var canExpand: Bool {
        !expanded && allBuilds.count > builds.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DOSSpacing.lg) {
                if shownBuilds.isEmpty {
                    Text(verbatim: "NO CHANGELOG DATA")
                        .font(DOSTypography.bodyLarge)
                        .foregroundStyle(AmberTheme.amber)
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    ForEach(shownBuilds) { build in
                        BuildCard(
                            build: build,
                            linksActive: linksActive,
                            onSelectDestination: onSelectDestination
                        )
                        // Re-arm the cascade when the sheet re-presents.
                        .id(build.buildNumber)
                    }

                    if canExpand {
                        Button {
                            withAnimation(.easeOut(duration: 0.25)) { expanded = true }
                        } label: {
                            Text(verbatim: "SHOW ALL \(allBuilds.count) BUILDS")
                                .font(DOSTypography.mono(size: 13, weight: .bold))
                                .foregroundStyle(AmberTheme.cgaCyan)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, DOSSpacing.sm)
                                .overlay(
                                    Rectangle().stroke(AmberTheme.cgaCyan.opacity(0.6), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, DOSSpacing.md)
            .padding(.vertical, DOSSpacing.md)
        }
        .background(Color.black)
        .dosNavigationTitle("What's New")
    }
}

// MARK: - BuildCard

/// One `## [Build N]` block as a patch-notes card with a staged reveal.
private struct BuildCard: View {
    let build: ChangelogBuild
    let linksActive: Bool
    let onSelectDestination: (ChangelogDestination) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealedStages = 0

    /// Banner is stage 0; each section is a later stage.
    private var stageCount: Int { build.sections.count + 1 }

    /// Linked entries in this build, resolved to their destinations. Drives the
    /// VoiceOver custom actions so deep links are reachable even though the card
    /// collapses its children for a single read-through.
    private var linkedEntries: [(entry: ChangelogEntry, destination: ChangelogDestination)] {
        guard linksActive else { return [] }
        return build.sections.flatMap(\.entries).compactMap { entry in
            entry.destinationKey
                .flatMap(ChangelogDestination.init(key:))
                .map { (entry, $0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DOSSpacing.sm) {
            banner
                .stagedReveal(0, revealed: revealedStages)

            ForEach(Array(build.sections.enumerated()), id: \.offset) { index, section in
                sectionView(section)
                    .stagedReveal(index + 1, revealed: revealedStages)
            }
        }
        .padding(DOSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Rectangle().stroke(AmberTheme.amberDark.opacity(0.6), lineWidth: 1)
        )
        .onAppear(perform: runReveal)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilitySummary))
        // Deep links are tap targets for sighted users (onTapGesture); expose
        // them to VoiceOver as custom actions on the collapsed card.
        .accessibilityActions {
            ForEach(linkedEntries.indices, id: \.self) { index in
                Button(linkedEntries[index].entry.text) {
                    onSelectDestination(linkedEntries[index].destination)
                }
            }
        }
    }

    private var banner: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: "PATCH NOTES · BUILD \(build.displayName)")
                .font(DOSTypography.mono(size: 13, weight: .bold))
                .foregroundStyle(AmberTheme.amberLight)
                .dosGlowLarge(color: AmberTheme.amber.opacity(0.4))
            Spacer(minLength: DOSSpacing.xs)
            if !build.date.isEmpty {
                Text(verbatim: build.date)
                    .font(DOSTypography.caption)
                    .foregroundStyle(AmberTheme.amberDark)
            }
        }
    }

    private func sectionView(_ section: ChangelogSection) -> some View {
        VStack(alignment: .leading, spacing: DOSSpacing.xs) {
            Text(verbatim: section.group.rawValue.uppercased())
                .font(DOSTypography.mono(size: 11, weight: .bold))
                .foregroundStyle(Self.color(for: section.group))

            ForEach(section.entries.indices, id: \.self) { index in
                entryRow(section.entries[index], color: Self.color(for: section.group))
            }
        }
    }

    @ViewBuilder
    private func entryRow(_ entry: ChangelogEntry, color: Color) -> some View {
        let destination = linksActive ? entry.destinationKey.flatMap(ChangelogDestination.init(key:)) : nil

        HStack(alignment: .firstTextBaseline, spacing: DOSSpacing.xs) {
            Rectangle()
                .fill(color)
                .frame(width: 5, height: 5)
                .accessibilityHidden(true)

            // Verbatim (R9): never route dynamic changelog text through
            // LocalizedStringKey — its Markdown/format-specifier parsing would
            // turn an entry's `[label](url)` into a live link that bypasses the
            // closed-set ChangelogDestination routing.
            Text(verbatim: entry.text)
                .font(DOSTypography.bodySmall)
                .foregroundStyle(AmberTheme.amberLight)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if destination != nil {
                Image(systemName: "arrow.right.circle")
                    .font(DOSTypography.mono(size: 13, weight: .regular))
                    .foregroundStyle(AmberTheme.cgaCyan)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let destination { onSelectDestination(destination) }
        }
        .allowsHitTesting(destination != nil)
    }

    private func runReveal() {
        guard !reduceMotion else {
            // Static at full brightness — no cascade.
            revealedStages = stageCount
            return
        }
        Task { @MainActor in
            for stage in 0 ..< stageCount {
                withAnimation(.easeOut(duration: 0.3)) {
                    revealedStages = stage + 1
                }
                try? await Task.sleep(for: .milliseconds(140))
            }
        }
    }

    /// One punctuated sentence per card for VoiceOver.
    private var accessibilitySummary: String {
        var parts = ["Build \(build.displayName)" + (build.date.isEmpty ? "" : ", \(build.date)")]
        for section in build.sections {
            let entries = section.entries.map(\.text).joined(separator: ". ")
            parts.append("\(section.group.rawValue): \(entries)")
        }
        return parts.joined(separator: ". ")
    }

    /// Color-coded section labels off the CGA palette (R9).
    private static func color(for group: ChangelogSection.Group) -> Color {
        switch group {
        case .added: return AmberTheme.cgaGreen
        case .changed: return AmberTheme.amber
        case .fixed: return AmberTheme.cgaCyan
        case .removed: return AmberTheme.cgaRed
        }
    }
}
