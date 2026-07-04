//
//  FoodImpactView.swift
//  DOSBTS
//

import SwiftUI

// MARK: - FoodImpactView

struct FoodImpactView: View {
    @EnvironmentObject var store: DirectStore

    var body: some View {
        Group {
            if scoredFoods.isEmpty {
                DOSEmptyState(
                    title: "NO SCORED FOODS YET",
                    detail: "Scores accumulate automatically from clean meals — no correction bolus, exercise, or stacked meal in the 2 h post-meal window."
                )
                .padding(.top, DOSSpacing.lg)
            } else {
                List {
                    Section(footer: footerView) {
                        ForEach(scoredFoods) { food in
                            FoodImpactRow(food: food)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .dosNavigationTitle("FOOD IMPACT")
        .onAppear {
            scoredFoods = store.state.scoredPersonalFoodValues
        }
        .onChange(of: store.state.scoredPersonalFoodValues) { _, values in
            scoredFoods = values
        }
    }

    // MARK: Private

    @State private var scoredFoods: [PersonalFood] = []

    private var footerView: some View {
        Text("Personal averages from clean-meal observations — reference only.")
            .font(DOSTypography.caption)
            .foregroundStyle(AmberTheme.amberDark)
            .padding(.top, DOSSpacing.xs)
    }
}

// MARK: - FoodImpactRow

private struct FoodImpactRow: View {
    let food: PersonalFood

    var body: some View {
        HStack {
            Text(food.name.uppercased())
                .font(DOSTypography.body)
                .foregroundStyle(rowColor)

            Spacer()

            HStack(alignment: .firstTextBaseline, spacing: DOSSpacing.xs) {
                if let avg = food.avgDeltaMgDL {
                    let sign = avg >= 0 ? "+" : ""
                    Text("\(sign)\(Int(avg.rounded()))")
                        .font(DOSTypography.body)
                        .foregroundStyle(deltaColor)
                    Text("avg · n=\(food.observationCount)")
                        .font(DOSTypography.caption)
                        .foregroundStyle(rowColor)
                }
            }
        }
        .padding(.vertical, DOSSpacing.xs)
    }

    private var isLowConfidence: Bool { food.observationCount < 3 }
    private var rowColor: Color { isLowConfidence ? AmberTheme.amberDark : AmberTheme.amber }
    private var deltaColor: Color {
        guard let avg = food.avgDeltaMgDL else { return AmberTheme.amberDark }
        return isLowConfidence ? AmberTheme.amberDark : mealImpactDeltaColor(delta: Int(avg.rounded()))
    }
}
