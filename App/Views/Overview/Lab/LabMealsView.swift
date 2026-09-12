//
//  LabMealsView.swift
//  DOSBTS
//
//  LAB: MEALS (DMNC-1500) — the lab chart plus its legend and safety footer.
//  P0 shipped the platform: the chart, the instrument cursors, and no overlays.
//  P2 (DMNC-1501) fills the meal overlays, appends their legend items, and adds
//  the one control the chart itself cannot carry: `STILL <TAG>? Y / N`, which is
//  how an open regime band gets an end.
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
                followStatus: $followStatus
            )

            if let band = openRegime {
                regimePrompt(band)
            }

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
                LabLegendItem(glyph: "A→B", label: "MEASURES", color: AmberTheme.amberLight),
                LabLegendItem.follow(followStatus),
            ])
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            LabFooter()
        }
        .onAppear { now = Date() }
        .onReceive(clock) { now = $0 }
    }

    // MARK: Private

    /// Owned here so the legend and the chart's `◂ N NEW` nub can never disagree
    /// about whether the view is pinned to the newest reading.
    @State private var followStatus: LabFollowStatus = .following

    /// A regime's default end passes while the app is open, so the prompt needs
    /// a clock. Once a minute — the same cadence as the hero's IOB refresh —
    /// because the rule it feeds has a 30-minute lead.
    @State private var now: Date = .init()

    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    /// Derived, never stored: the same pure deriver the chart's bands come from.
    private var openRegime: RegimeBand? {
        RegimePrompt.shouldShow(
            bands: RegimeDeriver.derive(
                notes: store.state.journalNoteValues,
                now: now,
                dayEnd: Calendar.current
                    .startOfDay(for: store.state.selectedDate ?? now)
                    .addingTimeInterval(24 * 60 * 60)
            ),
            now: now
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
        .dosCard(.panel, padding: DOSSpacing.xs)
        .padding(.horizontal, DOSSpacing.sm)
        .padding(.top, DOSSpacing.xs)
    }

    private func promptButton(
        _ title: String,
        accessibility: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(DOSTypography.mono(size: 12, weight: .semibold))
                .foregroundStyle(AmberTheme.amber)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .overlay(Rectangle().stroke(AmberTheme.amberDark, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }
}
