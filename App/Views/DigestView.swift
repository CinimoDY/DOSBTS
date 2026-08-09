//
//  DigestView.swift
//  DOSBTSApp
//

import SwiftUI

// MARK: - DigestView

struct DigestView: View {
    @EnvironmentObject var store: DirectStore
    @EnvironmentObject var sheets: SheetCoordinator

    @State private var selectedDate: Date = Date()
    @State private var hasAppeared: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: DOSSpacing.md) {
                dateNavigationBar

                if store.state.dailyDigestLoading {
                    loadingView
                } else if let digest = store.state.currentDailyDigest {
                    statsGrid(digest: digest)
                    aiInsightCard(digest: digest)
                    eventTimeline
                } else {
                    noDataView
                }
            }
            .padding(.horizontal, DOSSpacing.md)
            .padding(.top, DOSSpacing.sm)
        }
        .background(AmberTheme.dosBlack)
        // Slim glucose strip at the top — the value sits where the
        // Overview hero puts it, on every tab (R7b).
        .safeAreaInset(edge: .top, spacing: 0) {
            GlucoseTopBar()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            GlucoseStatusBar()
        }
        .onAppear {
            if !hasAppeared {
                hasAppeared = true
                store.dispatch(.loadDailyDigest(date: selectedDate))
            }
        }
        .onChange(of: store.state.dailyDigestLoading) { _, isLoading in
            if !isLoading, store.state.currentDailyDigest != nil {
                DirectNotifications.shared.hapticFeedback(.light)
            }
        }
    }

    // MARK: - Date Navigation

    private var dateNavigationBar: some View {
        HStack {
            Button(action: { navigateDate(by: -1) }) {
                Text("<")
                    .font(DOSTypography.bodyLarge)
                    .foregroundStyle(AmberTheme.amberDark)
            }

            Spacer()

            Text(dateLabel)
                .font(DOSTypography.bodyLarge)
                .foregroundStyle(AmberTheme.amber)

            Spacer()

            Button(action: { navigateDate(by: 1) }) {
                Text(">")
                    .font(DOSTypography.bodyLarge)
                    .foregroundStyle(isToday ? AmberTheme.borderFaint : AmberTheme.amberDark)
            }
            .disabled(isToday)

            // Second capture surface for journal notes. Lives in the date bar
            // rather than the timeline header so it stays reachable on a day
            // with no digest data. Presents through the app's single
            // presentation root — never a local .sheet (R8a).
            Button {
                sheets.present(.journalNote)
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(DOSTypography.body)
                    .foregroundStyle(AmberTheme.amber)
                    .accessibilityLabel("Add note")
            }
            .padding(.leading, DOSSpacing.md)
        }
        .padding(.vertical, DOSSpacing.sm)
    }

    // MARK: - Stats Grid

    private func statsGrid(digest: DailyDigest) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: DOSSpacing.sm),
            GridItem(.flexible(), spacing: DOSSpacing.sm),
            GridItem(.flexible(), spacing: DOSSpacing.sm),
        ], spacing: DOSSpacing.sm) {
            StatCard(
                label: "TIR",
                value: "\(Int(digest.tir))%",
                valueColor: tirColor(digest.tir),
                help: tirHelp(digest.tir)
            )
            StatCard(
                label: "LOWS",
                value: "\(digest.lowCount)",
                valueColor: digest.lowCount > 0 ? AmberTheme.cgaRed : AmberTheme.cgaGreen
            )
            StatCard(
                label: "HIGHS",
                value: "\(digest.highCount)",
                valueColor: digest.highCount > 0 ? AmberTheme.amber : AmberTheme.cgaGreen
            )
            StatCard(
                label: "AVG",
                value: "\(Int(digest.avg))",
                valueColor: AmberTheme.amber,
                help: store.state.glucoseUnit.localizedDescription
            )
            StatCard(
                label: "CARBS",
                value: "\(Int(digest.totalCarbsGrams))g",
                valueColor: AmberTheme.amber
            )
            StatCard(
                label: "INSULIN",
                value: String(format: "%.1fU", digest.totalInsulinUnits),
                valueColor: AmberTheme.amber
            )
        }
    }

    // MARK: - AI Insight Card

    private func aiInsightCard(digest: DailyDigest) -> some View {
        VStack(alignment: .leading, spacing: DOSSpacing.sm) {
            HStack {
                Text("AI INSIGHT")
                    .dosHeader(AmberTheme.cgaCyan)
                Spacer()
                if digest.aiInsight != nil {
                    Button(action: {
                        store.dispatch(.generateDailyDigestInsight(date: selectedDate, force: true))
                    }) {
                        Text("REFRESH")
                            .font(DOSTypography.caption)
                            .foregroundStyle(AmberTheme.amberDark)
                    }
                }
            }

            if store.state.dailyDigestInsightLoading {
                Text("ANALYZING...")
                    .font(DOSTypography.body)
                    .foregroundStyle(AmberTheme.amber)
                    .opacity(0.7)
            } else if let insight = digest.aiInsight, !insight.isEmpty {
                if let structured = DigestInsight.parse(insight) {
                    DigestInsightCard(insight: structured)
                        // Re-run the reveal cascade when the day changes.
                        .id(digest.date)
                } else {
                    // Pre-structured-format insights render as before.
                    AIInsightContent(text: insight)
                }
            } else if !store.state.aiConsentDailyDigest {
                Text("ENABLE AI INSIGHTS IN SETTINGS")
                    .font(DOSTypography.caption)
                    .foregroundStyle(AmberTheme.amber)
            } else if KeychainService.read(key: ClaudeService.keychainKey) == nil {
                Text("ADD API KEY IN SETTINGS")
                    .font(DOSTypography.caption)
                    .foregroundStyle(AmberTheme.amber)
            } else {
                Button(action: {
                    store.dispatch(.generateDailyDigestInsight(date: selectedDate, force: true))
                }) {
                    Text("INSIGHT UNAVAILABLE — TAP TO RETRY")
                        .font(DOSTypography.caption)
                        .foregroundStyle(AmberTheme.amber)
                }
            }
        }
        .dosCard(.info)
    }

    // MARK: - Event Timeline

    private var eventTimeline: some View {
        VStack(alignment: .leading, spacing: DOSSpacing.xs) {
            Text("TIMELINE")
                .dosHeader(AmberTheme.amber)
                .padding(.bottom, 4)

            if let events = store.state.dailyDigestEvents {
                let timelineItems = buildTimelineItems(events: events)
                if timelineItems.isEmpty {
                    Text("NO EVENTS LOGGED")
                        .font(DOSTypography.caption)
                        .foregroundStyle(AmberTheme.amber)
                } else {
                    ForEach(timelineItems, id: \.id) { item in
                        HStack(spacing: DOSSpacing.sm) {
                            Text(item.timeString)
                                .font(DOSTypography.caption)
                                .foregroundStyle(AmberTheme.amber)
                                .frame(width: 45, alignment: .leading)
                            Text(item.label)
                                .font(DOSTypography.caption)
                                .foregroundStyle(item.color)
                        }
                    }
                }
            } else {
                Text("LOADING...")
                    .font(DOSTypography.caption)
                    .foregroundStyle(AmberTheme.amber)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Loading / No Data States

    private var loadingView: some View {
        VStack(spacing: DOSSpacing.md) {
            Spacer()
            FiguresLoadingView(dotSize: DOSSpacing.xs, spacing: DOSSpacing.xxs)
            Text("LOADING...")
                .font(DOSTypography.bodyLarge)
                .foregroundStyle(AmberTheme.amber)
            Spacer()
        }
        .frame(minHeight: 200)
    }

    private var noDataView: some View {
        VStack {
            Spacer()
            DOSEmptyState(title: "NO DATA FOR THIS DAY")
            Spacer()
        }
        .frame(minHeight: 200)
    }

    // MARK: - Helpers

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM d"
        return formatter.string(from: selectedDate).uppercased()
    }

    private func navigateDate(by days: Int) {
        guard let newDate = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) else { return }
        guard newDate <= Date() else { return }
        selectedDate = newDate
        store.dispatch(.loadDailyDigest(date: newDate))
    }

}

// MARK: - AI Insight Content

/// Renders the daily-digest insight text with paragraph + bullet structure.
/// The AI prompt asks for a short opening paragraph followed by 2–4
/// bullet points starting with `- `; this view splits the response
/// accordingly and renders bullets with a cgaCyan glyph.
///
/// Falls back gracefully: if the response has no bullets, it renders as
/// a single paragraph; old cached insights from previous prompt
/// versions still display correctly.
// MARK: - Structured insight card (DOS infographic)

/// Renders the structured DigestInsight as a small DOS infographic:
/// grade-tinted headline, fact chips, "> " prompt tips, and an earned
/// cheer line with a phosphor pulse — revealed as a staged CRT cascade.
private struct DigestInsightCard: View {
    let insight: DigestInsight

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealedStages = 0
    @State private var cheerPulse = false

    private var gradeColor: Color {
        switch insight.grade {
        case .good: return AmberTheme.cgaGreen
        case .mixed: return AmberTheme.amber
        case .rough: return AmberTheme.cgaRed
        }
    }

    private func toneColor(_ tone: DigestInsight.Tone) -> Color {
        switch tone {
        case .good: return AmberTheme.cgaGreen
        case .warn: return AmberTheme.amber
        case .bad: return AmberTheme.cgaRed
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DOSSpacing.sm) {
            // Stage 0: headline with grade block glyph
            HStack(spacing: DOSSpacing.xs) {
                Rectangle()
                    .fill(gradeColor)
                    .frame(width: 6, height: 14)
                    .accessibilityHidden(true)
                Text(verbatim: insight.headline)
                    .font(DOSTypography.mono(size: 15, weight: .bold))
                    .foregroundStyle(AmberTheme.amberLight)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .stagedReveal(0, revealed: revealedStages)

            // Stage 1: fact chips
            if !insight.facts.isEmpty {
                HStack(spacing: DOSSpacing.xs) {
                    ForEach(insight.facts.indices, id: \.self) { idx in
                        let fact = insight.facts[idx]
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: fact.label)
                                .font(DOSTypography.mono(size: 9, weight: .medium))
                                .foregroundStyle(AmberTheme.amber)
                                .lineLimit(1)
                            Text(verbatim: fact.value)
                                .font(DOSTypography.mono(size: 14, weight: .bold))
                                .foregroundStyle(toneColor(fact.tone))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .padding(.horizontal, DOSSpacing.xs)
                        .padding(.vertical, DOSSpacing.xxs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(
                            Rectangle()
                                .stroke(toneColor(fact.tone).opacity(0.5), lineWidth: 1)
                        )
                    }
                }
                .stagedReveal(1, revealed: revealedStages)
            }

            // Stage 2: tips as prompt lines
            if !insight.tips.isEmpty {
                VStack(alignment: .leading, spacing: DOSSpacing.xs) {
                    ForEach(insight.tips.indices, id: \.self) { idx in
                        HStack(alignment: .firstTextBaseline, spacing: DOSSpacing.xs) {
                            Text(verbatim: ">")
                                .font(DOSTypography.mono(size: 13, weight: .bold))
                                .foregroundStyle(AmberTheme.cgaCyan)
                            Text(verbatim: insight.tips[idx])
                                .font(DOSTypography.bodySmall)
                                .foregroundStyle(AmberTheme.amberLight)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .stagedReveal(2, revealed: revealedStages)
            }

            // Stage 3: earned cheer with phosphor pulse
            if let cheer = insight.cheer {
                HStack(spacing: DOSSpacing.xs) {
                    Text(verbatim: "★")
                        .font(DOSTypography.mono(size: 12, weight: .bold))
                    Text(verbatim: cheer)
                        .font(DOSTypography.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(AmberTheme.cgaGreen)
                .dosGlowLarge(color: AmberTheme.cgaGreen.opacity(cheerPulse ? 0.9 : 0.3))
                .opacity(cheerPulse ? 1 : 0.82)
                .stagedReveal(3, revealed: revealedStages)
            }
        }
        .onAppear {
            guard !reduceMotion else {
                // No cascade, no pulse — everything static at full brightness.
                revealedStages = 4
                cheerPulse = true
                return
            }
            // CRT boot cascade. Async-stepped, not a synchronous
            // withAnimation loop: same-tick writes to one @State coalesce
            // into a single fade instead of staggering.
            Task { @MainActor in
                for stage in 0...3 {
                    withAnimation(AnimationTokens.easeReveal) {
                        revealedStages = stage + 1
                    }
                    try? await Task.sleep(for: .milliseconds(180))
                }
                withAnimation(AnimationTokens.pulse) {
                    cheerPulse = true
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilitySummary))
    }

    /// One punctuated sentence instead of a run-on of combined children.
    private var accessibilitySummary: String {
        var parts = [insight.headline]
        parts.append(contentsOf: insight.facts.map { "\($0.label): \($0.value)" })
        parts.append(contentsOf: insight.tips.map { "Tip: \($0)" })
        if let cheer = insight.cheer { parts.append(cheer) }
        return parts.joined(separator: ". ")
    }
}

/// Legacy fallback renderer: insights saved before the structured JSON
/// format (paragraph + "- " bullets), and any response DigestInsight.parse
/// rejects, render as plain text via this view.
private struct AIInsightContent: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks.indices, id: \.self) { idx in
                switch blocks[idx] {
                case .paragraph(let s):
                    Text(LocalizedStringKey(s))
                        .font(DOSTypography.body)
                        .foregroundStyle(AmberTheme.amberLight)
                        .fixedSize(horizontal: false, vertical: true)
                case .bullet(let s):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .font(DOSTypography.body)
                            .foregroundStyle(AmberTheme.cgaCyan)
                        Text(LocalizedStringKey(s))
                            .font(DOSTypography.body)
                            .foregroundStyle(AmberTheme.amberLight)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var paragraphLines: [String] = []

        func flushParagraph() {
            if !paragraphLines.isEmpty {
                result.append(.paragraph(paragraphLines.joined(separator: " ")))
                paragraphLines = []
            }
        }

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushParagraph()
            } else if trimmed.hasPrefix("- ") {
                flushParagraph()
                result.append(.bullet(String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("• ") {
                flushParagraph()
                result.append(.bullet(String(trimmed.dropFirst(2))))
            } else {
                paragraphLines.append(trimmed)
            }
        }
        flushParagraph()
        return result
    }

    private enum Block: Hashable {
        case paragraph(String)
        case bullet(String)
    }
}

// MARK: - Timeline Item

private struct TimelineItem: Identifiable {
    let id = UUID()
    let timestamp: Date
    let timeString: String
    let label: String
    let color: Color
}

private func buildTimelineItems(events: DailyDigestEvents) -> [TimelineItem] {
    let timeFormatter = DateFormatter()
    timeFormatter.dateFormat = "HH:mm"

    var items: [TimelineItem] = []

    for meal in events.meals {
        let carbs = meal.carbsGrams.map { "\(Int($0))g" } ?? "?"
        items.append(TimelineItem(
            timestamp: meal.timestamp,
            timeString: timeFormatter.string(from: meal.timestamp),
            label: "\(meal.mealDescription) \(carbs)",
            color: AmberTheme.amber
        ))
    }

    for ins in events.insulin {
        items.append(TimelineItem(
            timestamp: ins.starts,
            timeString: timeFormatter.string(from: ins.starts),
            label: "\(String(format: "%.1f", ins.units))U \(ins.type.description)",
            color: AmberTheme.cgaCyan
        ))
    }

    for ex in events.exercise {
        items.append(TimelineItem(
            timestamp: ex.startTime,
            timeString: timeFormatter.string(from: ex.startTime),
            label: "\(ex.activityType) \(Int(ex.durationMinutes))min",
            color: AmberTheme.cgaGreen
        ))
    }

    for note in events.notes {
        let tag = note.tag.map { "[\($0.localizedDescription)] " } ?? ""
        items.append(TimelineItem(
            timestamp: note.timestamp,
            timeString: timeFormatter.string(from: note.timestamp),
            label: "\(tag)\(note.text)",
            color: AmberTheme.amberLight
        ))
    }

    return items.sorted { $0.timestamp < $1.timestamp }
}
