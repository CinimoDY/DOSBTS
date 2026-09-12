//
//  LabFigure.swift
//  DOSBTS
//
//  Chart Lab (DMNC-1500) — a number the lab is allowed to show.
//
//  The lab's one hard rule about numbers: every derived figure ships with the
//  sample size it came from. That is enforced by the TYPE, not by discipline —
//  there is no initializer without `n`, so a figure cannot be constructed
//  without saying how many readings are behind it.
//
//  Pure and target-shared (`Library/` compiles into the widget): no SwiftUI.
//

import Foundation

struct LabFigure: Equatable, Codable {
    // MARK: Lifecycle

    /// The ONLY initializer. `n` is not optional and has no default — a figure
    /// without its sample size is a claim, and the lab never makes claims.
    init(
        kind: Kind,
        value: Double,
        unit: String,
        n: Int,
        spread: ClosedRange<Double>? = nil,
        window: DateInterval? = nil
    ) {
        self.kind = kind
        self.value = value
        self.unit = unit
        self.n = n
        self.spread = spread
        self.window = window
    }

    // MARK: Internal

    enum Kind: String, Codable {
        case delta
        case peakMinutes
        case glucose
        case iob
        case cob
        case count
        case median
        case percentile
        case duration
    }

    let kind: Kind
    let value: Double
    let unit: String
    let n: Int
    let spread: ClosedRange<Double>?
    let window: DateInterval?
}
