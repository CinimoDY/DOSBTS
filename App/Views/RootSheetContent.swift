//
//  RootSheetContent.swift
//  DOSBTS
//
//  Sheet content for the app's single presentation root (R8a). Hosted by
//  ContentView's `.sheet(item:)`; routes nested dismiss-then-present flows
//  back through the SheetCoordinator.
//

import SwiftUI

struct RootSheetContent: View {
    @EnvironmentObject var store: DirectStore
    @EnvironmentObject var sheets: SheetCoordinator
    @EnvironmentObject var addedHighlighter: AddedEntryHighlighter
    @EnvironmentObject var loggedEntryToast: LoggedEntryToastController

    let sheet: ActiveSheet

    var body: some View {
        switch sheet {
        case .insulin:
            // currentIOB is a live computed property inside AddInsulinView
            // (reads from the same store via @EnvironmentObject), so the
            // stacking warning stays accurate if the user adjusts basal DIA
            // or a new delivery lands while this sheet is open.
            //
            // Batch staging (DMNC-1413): CONFIRM commits every staged entry
            // plus the current form in one dispatch, not one-at-a-time.
            AddInsulinView(
                addCallback: { deliveries in
                    store.dispatch(.addInsulinDelivery(insulinDeliveryValues: deliveries))
                    for delivery in deliveries {
                        addedHighlighter.flash(delivery.id)
                    }
                    DirectNotifications.shared.hapticNotification(.success)
                    if deliveries.count == 1, let only = deliveries.first {
                        loggedEntryToast.stage(.insulin(only))
                    } else {
                        loggedEntryToast.stage(.insulinBatch(deliveries))
                    }
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
                addedHighlighter.flash(glucose.id)
                DirectNotifications.shared.hapticNotification(.success)
                loggedEntryToast.stage(.bloodGlucose(glucose))
            }

        case .treatmentModal(let alarmFiredAt):
            TreatmentModalView(
                alarmFiredAt: alarmFiredAt,
                onMoreTapped: {
                    // Stage the filtered entry sheet — presented via
                    // onDismiss after this modal closes.
                    sheets.dismissThenPresent(.filteredFoodEntry)
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
                    sheets.dismissThenPresent(.filteredFoodEntry)
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
                    sheets.dismissThenPresent(.combinedEntryEdit(group))
                },
                onDismiss: { sheets.dismiss() }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)

        case .combinedEntryEdit(let group):
            CombinedEntryEditView(originalGroup: group)
                .environmentObject(store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)

        case let .whatsNew(builds, allBuilds):
            // Own NavigationStack so the title bar + Done button render in the
            // sheet. Linked entries dismiss-then-navigate (KTD6): no nested
            // sheet — the destination just switches tab / pushes a Settings
            // category. lastSeenBuild already advanced at present time (KTD5),
            // so the dismiss path needs no special handling.
            NavigationStack {
                WhatsNewView(
                    builds: builds,
                    allBuilds: allBuilds,
                    linksActive: true,
                    onSelectDestination: { destination in
                        sheets.dismiss()
                        for action in destination.actions() {
                            store.dispatch(action)
                        }
                    }
                )
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { sheets.dismiss() }
                            .foregroundStyle(AmberTheme.amberLight)
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Helpers

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
}
