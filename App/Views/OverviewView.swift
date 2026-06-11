//
//  OverviewView.swift
//  DOSBTS
//

import SwiftUI

// MARK: - Active Sheet Enum (prevents SwiftUI sibling-sheet collisions)

private enum ActiveSheet: Identifiable {
    case insulin
    case meal
    case bloodGlucose
    case treatmentModal(alarmFiredAt: Date)
    case filteredFoodEntry
    case treatmentRecheck(glucoseValue: Int)
    case entryGroupReadOverlay(ConsolidatedMarkerGroup)
    case combinedEntryEdit(ConsolidatedMarkerGroup)

    var id: String {
        switch self {
        case .insulin: return "insulin"
        case .meal: return "meal"
        case .bloodGlucose: return "bloodGlucose"
        case .treatmentModal: return "treatmentModal"
        case .filteredFoodEntry: return "filteredFoodEntry"
        case .treatmentRecheck: return "treatmentRecheck"
        case .entryGroupReadOverlay(let g): return "entryGroupReadOverlay-\(g.id)"
        case .combinedEntryEdit(let g): return "combinedEntryEdit-\(g.id)"
        }
    }
}

struct OverviewView: View {
    @EnvironmentObject var store: DirectStore

    @State private var activeSheet: ActiveSheet?
    @State private var pendingSheet: ActiveSheet?
    @State private var selectedReportType: ReportType = .glucose

    var body: some View {
        VStack(spacing: 0) {
            GlucoseView()

            SensorLineView()

            // Treatment countdown banner (between sensor line and chart toolbar)
            if store.state.treatmentCycleActive {
                TreatmentBannerView()
            }

            ChartReportTypeRow(selectedReportType: $selectedReportType)

            if !store.state.sensorGlucoseValues.isEmpty || !store.state.bloodGlucoseValues.isEmpty {
                ChartView(
                    selectedReportType: selectedReportType,
                    onTapMarkerGroup: { group in
                        activeSheet = .entryGroupReadOverlay(group)
                    }
                )
                .frame(maxHeight: .infinity)

                ChartZoomRow(selectedReportType: selectedReportType)
            } else {
                Spacer()
            }
        }
        .background(AmberTheme.dosBlack)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StickyQuickActions()
        }
        .sheet(item: $activeSheet, onDismiss: {
            // Present pending sheet after current one fully dismisses (avoids asyncAfter timing hack)
            if let pending = pendingSheet {
                pendingSheet = nil
                activeSheet = pending
            }
        }) { sheet in
            sheetContent(for: sheet)
        }
        .onAppear {
            // Handle cold launch: showTreatmentPrompt may already be true before onChange subscribes
            if store.state.showTreatmentPrompt, let alarmFiredAt = store.state.alarmFiredAt {
                activeSheet = .treatmentModal(alarmFiredAt: alarmFiredAt)
                store.dispatch(.setShowTreatmentPrompt(show: false))
            }
        }
        .onChange(of: store.state.showTreatmentPrompt) { _, newValue in
            if newValue, let alarmFiredAt = store.state.alarmFiredAt {
                activeSheet = .treatmentModal(alarmFiredAt: alarmFiredAt)
                store.dispatch(.setShowTreatmentPrompt(show: false))
            }
        }
        .onChange(of: store.state.recheckDispatched) { _, newValue in
            guard newValue, store.state.treatmentCycleActive else { return }
            // Check if still low — show recheck modal
            if let glucose = store.state.latestSensorGlucose,
               glucose.glucoseValue < store.state.alarmLow {
                activeSheet = .treatmentRecheck(glucoseValue: glucose.glucoseValue)
            }
            // If recovered, the banner handles the "STABILISED" state
        }
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .insulin:
            // currentIOB is now a live computed property inside AddInsulinView
            // (reads from the same store via @EnvironmentObject), so the
            // stacking warning stays accurate if the user adjusts basal DIA
            // or a new delivery lands while this sheet is open.
            AddInsulinView(
                addCallback: { start, end, units, insulinType in
                    let insulinDelivery = InsulinDelivery(id: UUID(), starts: start, ends: end, units: units, type: insulinType)
                    store.dispatch(.addInsulinDelivery(insulinDeliveryValues: [insulinDelivery]))
                }
            )
            .environmentObject(store)

        case .meal:
            UnifiedFoodEntryView()
                .environmentObject(store)

        case .bloodGlucose:
            AddBloodGlucoseView(glucoseUnit: store.state.glucoseUnit) { time, value in
                let glucose = BloodGlucose(id: UUID(), timestamp: time, glucoseValue: value)
                store.dispatch(.addBloodGlucose(glucoseValues: [glucose]))
            }

        case .treatmentModal(let alarmFiredAt):
            TreatmentModalView(
                alarmFiredAt: alarmFiredAt,
                onMoreTapped: {
                    // Set pending sheet — will be presented via onDismiss after this modal closes
                    pendingSheet = .filteredFoodEntry
                    activeSheet = nil
                }
            )
            .environmentObject(store)

        case .filteredFoodEntry:
            UnifiedFoodEntryView(filterToHypoTreatments: true)
                .environmentObject(store)

        case .treatmentRecheck(let glucoseValue):
            TreatmentModalView(
                alarmFiredAt: store.state.alarmFiredAt ?? Date(),
                onMoreTapped: {
                    pendingSheet = .filteredFoodEntry
                    activeSheet = nil
                },
                isRecheckMode: true,
                recheckGlucoseValue: glucoseValue
            )
            .environmentObject(store)

        case .entryGroupReadOverlay(let group):
            EntryGroupListOverlay(
                group: group,
                mealEntries: store.state.mealEntryValues,
                insulinDeliveries: store.state.insulinDeliveryValues,
                exerciseEntries: store.state.exerciseEntryValues,
                mealImpacts: computeMealImpactsDict(for: group),
                personalFoodAvgs: computePersonalFoodAvgsDict(for: group),
                glucoseUnit: store.state.glucoseUnit,
                iobAtTime: { date in
                    let bolusModel = store.state.bolusInsulinPreset.model
                    let basalModel = ExponentialInsulinModel.basal(diaMinutes: store.state.basalDIAMinutes)
                    let result = computeIOB(
                        deliveries: store.state.iobDeliveries,
                        bolusModel: bolusModel,
                        basalModel: basalModel,
                        at: date
                    )
                    return result.total > 0.05 ? result.total : nil
                },
                confoundersFor: { meal in
                    let c = detectMealConfounders(
                        meal: meal,
                        insulinDeliveryValues: store.state.insulinDeliveryValues,
                        exerciseEntryValues: store.state.exerciseEntryValues,
                        mealEntryValues: store.state.mealEntryValues
                    )
                    var arr: [ConfounderType] = []
                    if c.hasCorrectionBolus { arr.append(.correctionBolus) }
                    if c.hasExercise { arr.append(.exercise) }
                    if c.hasStackedMeal { arr.append(.stackedMeal) }
                    return arr
                },
                onEdit: {
                    pendingSheet = .combinedEntryEdit(group)
                    activeSheet = nil
                },
                onDismiss: { activeSheet = nil }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)

        case .combinedEntryEdit(let group):
            CombinedEntryEditView(originalGroup: group)
                .environmentObject(store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Sheet Helpers

    private func computeMealImpactsDict(for group: ConsolidatedMarkerGroup) -> [UUID: MealImpact] {
        var dict: [UUID: MealImpact] = [:]
        for marker in group.markers where marker.type == .meal {
            guard let meal = store.state.mealEntryValues.first(where: { $0.id == marker.sourceID }) else { continue }
            let isInProgress = Date().timeIntervalSince(meal.timestamp) < 2 * 60 * 60
            let delta = computeMealOverlayDelta(
                meal: meal,
                isInProgress: isInProgress,
                sensorGlucoseValues: store.state.sensorGlucoseValues
            )
            if let d = delta.delta {
                dict[meal.id] = MealImpact(
                    mealEntryId: meal.id,
                    baselineGlucose: nil,
                    peakGlucose: 0,
                    deltaMgDL: d,
                    timeToPeakMinutes: 0,
                    isClean: true,
                    timestamp: meal.timestamp
                )
            }
        }
        return dict
    }

    private func computePersonalFoodAvgsDict(for group: ConsolidatedMarkerGroup) -> [UUID: PersonalFoodGlycemic] {
        var dict: [UUID: PersonalFoodGlycemic] = [:]
        for marker in group.markers where marker.type == .meal {
            guard let meal = store.state.mealEntryValues.first(where: { $0.id == marker.sourceID }),
                  let sessionId = meal.analysisSessionId,
                  let food = store.state.personalFoodValues.first(where: { $0.analysisSessionId == sessionId }),
                  food.observationCount >= 2,
                  let avg = food.avgDeltaMgDL
            else { continue }
            dict[meal.id] = PersonalFoodGlycemic(
                avgDelta: Int(avg),
                observationCount: food.observationCount
            )
        }
        return dict
    }

    // MARK: - Sticky Quick Actions

    @ViewBuilder
    private func StickyQuickActions() -> some View {
        VStack(spacing: 0) {
            Divider()
                .background(AmberTheme.dosBorder)

            HStack(spacing: DOSSpacing.sm) {
                if DirectConfig.showInsulinInput, store.state.showInsulinInput {
                    QuickActionButton(title: "INSULIN", action: { activeSheet = .insulin }) {
                        Image(systemName: "syringe")
                            .font(DOSTypography.body)
                    }
                }

                QuickActionButton(title: "MEAL", action: { activeSheet = .meal }) {
                    AppleIcon().frame(width: 16, height: 16)
                }
            }
            .padding(.horizontal, DOSSpacing.md)
            .padding(.vertical, DOSSpacing.xs)
            .background(AmberTheme.dosBlack)
        }
    }
}

// MARK: - Quick Action Button

private struct QuickActionButton<Icon: View>: View {
    let title: String
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        Button(action: action) {
            HStack(spacing: DOSSpacing.xs) {
                icon()
                    .frame(height: 16)
                Text(title)
                    .font(DOSTypography.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(DOSButtonStyle(variant: .ghost))
        .frame(maxWidth: .infinity)
    }
}
