//
//  LabMealsView.swift
//  DOSBTS
//
//  LAB: MEALS (DMNC-1500) — the lab chart plus its legend and safety footer.
//  P0 ships the platform: the chart, the instrument cursors, and no overlays.
//  P2 fills the meal overlays and appends its own legend items here.
//

import SwiftUI

struct LabMealsView: View {
    // MARK: Internal

    @EnvironmentObject var store: DirectStore

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
            ScrollView {
                VStack(spacing: 0) {
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

            LabLegendRow(items: [
                LabLegendItem(glyph: "A→B", label: "MEASURES", color: AmberTheme.amberLight),
                LabLegendItem(glyph: "●", label: "CITED FACT", color: AmberTheme.amber),
                LabLegendItem(glyph: "■", label: "HYPO ONSET", color: AmberTheme.cgaRed),
                LabLegendItem.follow(followStatus)
            ])

            LabFooter()
        }
        // A focus request is about a fact on THIS day; paging the chart retires
        // it (P0 clears its cursors on the same change).
        .onChange(of: store.state.selectedDate) { focusRequest = nil }
    }

    // MARK: Private

    private enum Config {
        /// The cards' share of the tab. Measured on an iPhone 17: the chart sits
        /// at its 140 pt floor and the legend + safety footer must still fit
        /// under it, so the facts region is capped and scrolls rather than
        /// pushing the footer off the bottom (the VStack overflow that sinks a
        /// safeAreaInset — docs/solutions/ui-bugs).
        static let factsMaxHeight: CGFloat = 120
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
}

// MARK: - LabFactsHeightKey

private struct LabFactsHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
