//
//  StagingPlateRowView.swift
//  DOSBTS
//

import SwiftUI

enum StagingPlateRowLogic {
    static func applyAmountChange(item: inout EditableFoodItem, newAmount: Double) {
        let clamped = min(max(newAmount, 0), 10000)
        item.currentAmountG = clamped
        if let ratio = item.carbsPerG {
            item.carbsG = ratio * clamped
        }
    }

    static func applyCarbsChange(item: inout EditableFoodItem, newCarbs: Double) {
        item.carbsG = newCarbs
        if let ratio = item.carbsPerG, let amt = item.currentAmountG {
            let expected = ratio * amt
            if abs(newCarbs - expected) > 0.5 {
                item.carbsPerG = nil
            }
        }
    }

    static func summary(for item: EditableFoodItem) -> String {
        if let amt = item.currentAmountG {
            return "\(Int(amt))g · \(Int(item.carbsG))g C"
        }
        return "\(Int(item.carbsG))g C"
    }
}

struct StagingPlateRowView: View {
    @Binding var item: EditableFoodItem
    var onBarcodeRescan: (UUID) -> Void = { _ in }
    var isExpanded: Bool
    var onToggleExpand: () -> Void

    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            collapsedHeader
            if isExpanded { expandedFields }
        }
    }

    private var collapsedHeader: some View {
        HStack {
            Text(item.name.isEmpty ? "New item" : item.name)
                .font(DOSTypography.body)
                .foregroundStyle(item.name.isEmpty ? AmberTheme.amberDark : AmberTheme.amber)
            Spacer()
            Text(StagingPlateRowLogic.summary(for: item))
                .font(DOSTypography.caption)
                .foregroundStyle(AmberTheme.amber)
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(DOSTypography.caption)
                .foregroundStyle(AmberTheme.amberDark)
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(AnimationTokens.easeStandard) { onToggleExpand() } }
    }

    @ViewBuilder
    private var expandedFields: some View {
        VStack(spacing: DOSSpacing.sm) {
            HStack {
                Text("Name").font(DOSTypography.caption).foregroundStyle(AmberTheme.amber)
                TextField("Food name", text: $item.name)
                    .multilineTextAlignment(.trailing)
                    .focused($isNameFocused)
                Button { onBarcodeRescan(item.id) } label: {
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 18))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(AmberTheme.amberDark)
                }
                .buttonStyle(.plain)
            }
            if item.currentAmountG != nil {
                HStack {
                    Text("Amount").font(DOSTypography.caption).foregroundStyle(AmberTheme.amber)
                    TextField("0", value: $item.currentAmountG, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .onChange(of: item.currentAmountG) { _, new in
                            guard let new else { return }
                            StagingPlateRowLogic.applyAmountChange(item: &item, newAmount: new)
                        }
                    Text("g").font(DOSTypography.caption).foregroundStyle(AmberTheme.amber)
                }
            }
            HStack {
                Text("Carbs").font(DOSTypography.caption).foregroundStyle(AmberTheme.amber)
                TextField("0", value: $item.carbsG, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .onChange(of: item.carbsG) { _, new in
                        StagingPlateRowLogic.applyCarbsChange(item: &item, newCarbs: new)
                    }
                Text("g").font(DOSTypography.caption).foregroundStyle(AmberTheme.amber)
                if item.carbsPerG == nil && item.currentAmountG != nil {
                    Text("manual")
                        .font(DOSTypography.caption)
                        .foregroundStyle(AmberTheme.amber)
                }
            }
        }
        .padding(.leading, DOSSpacing.md)
    }
}
