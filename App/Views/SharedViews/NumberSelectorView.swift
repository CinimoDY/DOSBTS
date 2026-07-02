//
//  NumberSelectorView.swift
//  DOSBTS
//

import SwiftUI

typealias NumberSelectorCompletionHandler = (_ value: Int) -> Void

// MARK: - NumberSelectorView

struct NumberSelectorView: View {
    // MARK: Lifecycle

    init(key: String, value: Int, step: Int, min: Int = 40, max: Int = 500, displayValue: String?, completionHandler: NumberSelectorCompletionHandler? = nil) {
        self.key = key
        self.value = value
        self.step = step
        self.displayValue = displayValue
        self.completionHandler = completionHandler
        self.min = Double(min)
        self.max = Double(max)
    }

    // MARK: Internal

    @State var value: Int

    let key: String
    var displayValue: String?
    let completionHandler: NumberSelectorCompletionHandler?
    let step: Int
    let min: Double
    let max: Double

    var doubleProxy: Binding<Double> {
        Binding<Double>(get: {
            Double(value)
        }, set: {
            value = Swift.min(Int(max), Swift.max(Int(min), Int($0)))
        })
    }

    var body: some View {
        VStack {
            HStack {
                Text(verbatim: key)
                Spacer()

                if let displayValue = displayValue {
                    Text(verbatim: displayValue)
                }
            }

            HStack {
                Button {
                    value = Swift.max(Int(min), value - step)
                } label: {
                    Image(systemName: "minus.square")
                }
                .frame(width: 40, height: 40, alignment: .leading)
                .font(DOSTypography.bodyLarge)
                .foregroundStyle(AmberTheme.amber)
                .buttonStyle(.borderless)

                Slider(value: doubleProxy, in: min ... max, step: Double(step)).onChange(of: value) { _, newValue in
                    if let completionHandler = completionHandler {
                        completionHandler(newValue)
                    }
                }

                Button {
                    value = Swift.min(Int(max), value + step)
                } label: {
                    Image(systemName: "plus.square")
                }
                .frame(width: 40, height: 40, alignment: .trailing)
                .font(DOSTypography.bodyLarge)
                .foregroundStyle(AmberTheme.amber)
                .buttonStyle(.borderless)
            }
        }
    }
}

// MARK: - NumberSelectorView_Previews

struct NumberSelectorView_Previews: PreviewProvider {
    static var previews: some View {
        NumberSelectorView(key: "Key", value: 10, step: 5, displayValue: "10 mg/dl")
    }
}
