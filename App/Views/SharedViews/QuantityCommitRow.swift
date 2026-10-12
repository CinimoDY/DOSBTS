//
//  QuantityCommitRow.swift
//  DOSBTS
//
//  Count-mode row (DMNC-1562): `[−] N [+]`, a live "× name · Ng" label,
//  ADD and cancel. The caller owns the session; this view only edits the
//  bound count and reports ADD / cancel.
//

import SwiftUI

struct QuantityCommitRow: View {
    let baseDescription: String
    let baseCarbs: Double?
    @Binding var count: Int
    let onAdd: () -> Void
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var countValue: Binding<Double?> {
        Binding(
            get: { Double(count) },
            set: { newValue in
                guard let newValue else { return }
                count = QuantityCommit.clamped(Int(newValue.rounded()))
            }
        )
    }

    private var totalLabel: String {
        let name = QuantityCommit.baseDescription(baseDescription)
        if let baseCarbs {
            return "× \(name) · \(Int((baseCarbs * Double(count)).rounded()))g"
        }
        return "× \(name)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DOSSpacing.xs) {
            StepperField(
                title: "Count",
                value: countValue,
                step: 1,
                range: Double(QuantityCommit.countRange.lowerBound)...Double(QuantityCommit.countRange.upperBound)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Count")
            .accessibilityValue("\(count)")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: count = QuantityCommit.clamped(count + 1)
                case .decrement: count = QuantityCommit.clamped(count - 1)
                @unknown default: break
                }
            }

            HStack(spacing: DOSSpacing.sm) {
                Text(verbatim: totalLabel)
                    .font(DOSTypography.bodySmall)
                    .foregroundStyle(AmberTheme.amber)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: DOSSpacing.xs)

                Button("ADD", action: onAdd)
                    .buttonStyle(.dosPrimary)

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(DOSTypography.caption)
                        .foregroundStyle(AmberTheme.amberDark)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel count")
            }
        }
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil }
        }
        .transition(reduceMotion ? .identity : .opacity.animation(AnimationTokens.easeStandard))
    }
}
