//
//  LabMealsView.swift
//  DOSBTS
//
//  LAB: MEALS (DMNC-1500) — the lab chart plus everything that cannot live
//  inside it. P0 shipped the platform (chart + instrument cursors); P5
//  (DMNC-1505) added the cited-facts region under the chart; P2 (DMNC-1501)
//  adds the meal overlays and the two controls the chart itself cannot carry:
//  the residual `TAP TO NOTE` rows and `STILL <TAG>? Y / N`.
//
//  Reading order under the chart is deliberate: what the user can ACT on comes
//  first (the prompts are short and fixed-height), then what they can READ
//  (the facts region, scrollable and height-capped).
//

import SwiftUI

struct LabMealsView: View {
    // MARK: Internal

    @EnvironmentObject var store: DirectStore
    @EnvironmentObject var sheets: SheetCoordinator

    var body: some View {
        VStack(spacing: 0) {
            LabChartView(
                overlays: ReportType.labMeals.labOverlays,
                followStatus: $followStatus,
                factsBinding: $facts,
                focusRequest: focusRequest
            )

            // The cited facts, under the chart they are about. Scrollable and
            // height-capped so five cards can never push the chart below its
            // floor (swiftui-vstack-overflow-sinks-safeareainset).
            //
            // P2's residual rows live INSIDE this region rather than beside it.
            // They are the same kind of thing as a fact card — something to
            // read, and optionally tap — and as fixed-height siblings they
            // overflowed the tab and sank the footer (measured on the
            // simulator: the hero clipped and `LAB · EXPERIMENTAL` disappeared
            // under the tab bar). Sharing one capped, scrollable budget is what
            // keeps the chart above its floor and the footer on screen.
            ScrollView {
                VStack(spacing: 0) {
                    // Actionable first, and in this order: the time-bounded
                    // question, then the unexplained excursion, then the facts.
                    // Both prompts are the FIRST things in the region, so they
                    // are visible without scrolling.
                    if let band = openRegime {
                        regimePrompt(band)
                    }

                    // The chart can show several `?`; each needs its own way in.
                    ForEach(residuals.suffix(Config.maxResidualRows)) { residual in
                        residualPrompt(residual)
                    }

                    LabFactSheetLine(sheet: facts.sheet, glucoseUnit: store.state.glucoseUnit)

                    LabFactCardList(
                        facts: facts.facts,
                        glucoseUnit: store.state.glucoseUnit,
                        onSelect: { focusRequest = LabFocusRequest(fact: $0) }
                    )
                }
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(key: LabFactsHeightKey.self, value: geometry.size.height)
                    }
                )
            }
            .scrollBounceBehavior(.basedOnSize)
            // Sized to its content, then capped. A `ScrollView` is greedy in its
            // scroll axis, so an uncapped one reserves the full budget even with
            // no facts at all and squeezes the chart toward its floor for
            // nothing — and `.fixedSize` "fixes" that by ignoring the cap
            // instead, which overflows the tab and draws cards over the legend
            // (seen on the simulator with three cards). Measuring is the only
            // shape that gets both ends right.
            .frame(height: min(factsHeight, Config.factsMaxHeight))
            .onPreferenceChange(LabFactsHeightKey.self) { factsHeight = $0 }

            // Three rows. Six items on one row still ran off both edges at
            // `minimumScaleFactor(0.6)` — each `Text` scales on its own, so the
            // ROW's width is never constrained — and an unreadable legend costs
            // more than the 20 pt a third row spends.
            LabLegendRow(items: [
                LabLegendItem(glyph: "●", label: "SIZE = CARBS", color: EventMarkerType.meal.color),
                LabLegendItem(glyph: "▮", label: "2H RESPONSE", color: AmberTheme.amber),
                LabLegendItem(glyph: "▨", label: "EXCLUDED · TAG = WHY", color: AmberTheme.amberDark),
            ])
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            LabLegendRow(items: [
                LabLegendItem(glyph: "▨", label: "REGIME", color: AmberTheme.amberLight),
                LabLegendItem(glyph: "?", label: "NO CAUSE", color: AmberTheme.amber),
                LabLegendItem(glyph: "●", label: "CITED FACT", color: AmberTheme.amber),
                LabLegendItem(glyph: "■", label: "HYPO ONSET", color: AmberTheme.cgaRed),
            ])
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            LabLegendRow(items: [
                LabLegendItem(glyph: "A→B", label: "MEASURES", color: AmberTheme.amberLight),
                LabLegendItem.follow(followStatus),
            ])
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            LabFooter()
        }
        .onAppear {
            now = Date()
            refreshResiduals()
        }
        .onReceive(clock) { now = $0 }
        .onChange(of: store.state.sensorGlucoseValues) { refreshResiduals() }
        .onChange(of: store.state.journalNoteValues) { refreshResiduals() }
        .onChange(of: store.state.mealEntryValues) { refreshResiduals() }
        .onChange(of: store.state.insulinDeliveryValues) { refreshResiduals() }
        .onChange(of: store.state.exerciseEntryValues) { refreshResiduals() }
        // A focus request is about a fact on THIS day; paging the chart retires
        // it (P0 clears its cursors on the same change). The residuals are
        // day-scoped too, so they are recomputed on the same edge.
        .onChange(of: store.state.selectedDate) {
            focusRequest = nil
            refreshResiduals()
        }
    }

    // MARK: Private

    private enum Config {
        /// The cards' share of the tab. Measured on an iPhone 17: the chart sits
        /// at its 140 pt floor and the legend + safety footer must still fit
        /// under it, so the facts region is capped and scrolls rather than
        /// pushing the footer off the bottom (the VStack overflow that sinks a
        /// safeAreaInset — docs/solutions/ui-bugs).
        static let factsMaxHeight: CGFloat = 120
        /// At most this many residual rows, newest last. One rather than three:
        /// the rows now share the facts region's budget, and a second row would
        /// push the sheet line out of view before the user has scrolled.
        static let maxResidualRows = 1
    }

    /// Owned here so the legend and the chart's `◂ N NEW` nub can never disagree
    /// about whether the view is pinned to the newest reading.
    @State private var followStatus: LabFollowStatus = .following
    /// Pushed up by the chart, so the pins and the cards are built from ONE
    /// computation of the facts rather than two that could disagree.
    @State private var facts: LabFactsSnapshot = .empty
    /// Set when a card is tapped; the chart scrolls to the anchor and drops a
    /// cursor on it.
    @State private var focusRequest: LabFocusRequest?
    /// Measured height of the sheet line + cards, so the region can size to its
    /// content and still be capped.
    @State private var factsHeight: CGFloat = 0

    /// A regime's default end passes while the app is open, so the prompt needs
    /// a clock. Once a minute — the same cadence as the hero's IOB refresh —
    /// because the rule it feeds has a 30-minute lead.
    @State private var now: Date = .init()

    /// Memoised so the detector runs when the data moves, not on every body
    /// evaluation.
    @State private var residuals: [ResidualSegment] = []

    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    /// The same next-midnight the chart's bands use (DST-safe).
    private var dayEnd: Date {
        LabChartSeriesBuilder.endOfDay(for: store.state.selectedDate ?? now)
    }

    /// A day you are only READING is not a day you can answer for: the notes
    /// are scoped to it, so an answer written at `now` would never come back.
    private var isLiveDay: Bool {
        guard let selected = store.state.selectedDate else { return true }
        return Calendar.current.isDateInToday(selected)
    }

    /// The same pure detector the chart's `?` marks come from, over the same
    /// anchors — so the row and the chart can never disagree about what is
    /// unexplained.
    private func refreshResiduals() {
        residuals = ResidualDetector.detect(
            readings: store.state.sensorGlucoseValues,
            anchors: ResidualDetector.anchors(
                meals: store.state.mealEntryValues,
                insulin: store.state.insulinDeliveryValues,
                exercise: store.state.exerciseEntryValues,
                notes: store.state.journalNoteValues
            ),
            regimes: RegimeDeriver.derive(notes: store.state.journalNoteValues, dayEnd: dayEnd)
        )
    }

    /// The residual's affordance. It lives HERE rather than on the chart's `?`
    /// because a view inside a scrollable `Chart` annotation never receives a
    /// tap — the scroll and selection gestures consume it. This row claims only
    /// its own frame, so it has no gesture to lose.
    private func residualPrompt(_ segment: ResidualSegment) -> some View {
        Button {
            // The note opens at the excursion's START — the moment the user is
            // being asked to remember, not the moment they tapped.
            sheets.present(.journalNote(prefill: JournalNotePrefill(
                timestamp: segment.start,
                tag: nil
            )))
            DirectNotifications.shared.hapticFeedback()
        } label: {
            HStack(spacing: DOSSpacing.xs) {
                Text(verbatim: "?")
                    .font(DOSTypography.mono(size: 13, weight: .bold))
                    .foregroundStyle(AmberTheme.amber)
                Text(ResidualDetector.label(for: segment, glucoseUnit: store.state.glucoseUnit))
                    .font(DOSTypography.micro)
                    .foregroundStyle(AmberTheme.amber)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .dosCard(.toast, padding: DOSSpacing.xs)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DOSSpacing.sm)
        .padding(.top, DOSSpacing.xs)
        .accessibilityLabel("Unexplained excursion, tap to add a note")
    }

    /// Derived, never stored: the same pure deriver the chart's bands come from.
    private var openRegime: RegimeBand? {
        RegimePrompt.shouldShow(
            bands: RegimeDeriver.derive(notes: store.state.journalNoteValues, dayEnd: dayEnd),
            now: now,
            isLiveDay: isLiveDay
        )
    }

    /// `STILL STRESSED? Y / N`. A question about context, never about treatment.
    private func regimePrompt(_ band: RegimeBand) -> some View {
        HStack {
            Text("STILL \(band.tag.localizedDescription)?")
                .font(DOSTypography.caption)
                .foregroundStyle(AmberTheme.amber)

            Spacer()

            HStack(spacing: DOSSpacing.xs) {
                promptButton("Y", accessibility: "Yes, still \(band.tag.localizedDescription)") {
                    // Open a fresh note at now, pre-tagged: saying "still" is
                    // saying it again, which is what extends the band.
                    sheets.present(.journalNote(prefill: JournalNotePrefill(
                        timestamp: now,
                        tag: band.tag
                    )))
                }
                promptButton("N", accessibility: "No longer \(band.tag.localizedDescription)") {
                    store.dispatch(.addJournalNote(journalNoteValues: [
                        JournalNote(
                            timestamp: now,
                            text: RegimeDeriver.closeMarkerText,
                            tag: nil
                        ),
                    ]))
                    DirectNotifications.shared.hapticNotification(.success)
                }
            }
        }
        // Tight on purpose: the 44-pt buttons ARE the row's height, and every
        // point of chrome around them comes off the chart above.
        .dosCard(.panel, padding: DOSSpacing.xxs)
        .padding(.horizontal, DOSSpacing.sm)
        .padding(.top, DOSSpacing.xxs)
    }

    private func promptButton(
        _ title: String,
        accessibility: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.dosGhost)
        .accessibilityLabel(accessibility)
    }
}

// MARK: - LabFactsHeightKey

private struct LabFactsHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
