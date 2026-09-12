//
//  LabCursorState.swift
//  DOSBTS
//
//  The Chart Lab's interaction logic, extracted from the view so it can be
//  pinned by tests rather than only by eye (DMNC-1500). Nothing here touches
//  SwiftUI state, the store, or Charts — `LabChartView` is the only caller and
//  it does nothing but forward events in and read results out.
//

import CoreGraphics
import Foundation

// MARK: - LabCursorState

/// The instrument cursors' state machine.
///
/// It is driven by one input — the `chartXSelection(value:)` binding, which is
/// non-nil while the finger is down and nil on release — and produces the two
/// things the chart renders: a sticky single cursor, or a sticky A→B range.
///
/// The cycle is: press → cursor · press again far enough away → A→B · press a
/// third time → back to a single cursor. A press that lands within `minRange`
/// of the standing cursor is a re-scrub, not a measurement.
struct LabCursorState: Equatable {
    // MARK: Internal

    /// The single sticky cursor, when there is no range.
    private(set) var cursor: Date?
    /// The sticky A→B measurement, ordered ascending.
    private(set) var range: ClosedRange<Date>?

    var isEmpty: Bool { cursor == nil && range == nil }

    /// Feed the selection binding straight in: a `Date` while the finger is
    /// down, `nil` on release.
    mutating func apply(selection: Date?, minRange: TimeInterval) {
        guard let date = selection else {
            // The binding resets to nil on release; everything above stays put.
            sessionActive = false
            return
        }

        if sessionActive {
            if anchor != nil {
                setRange(to: date)
            } else {
                cursor = date
            }
            return
        }

        sessionActive = true

        if let standing = cursor, range == nil, abs(date.timeIntervalSince(standing)) >= minRange {
            anchor = standing
            setRange(to: date)
        } else {
            anchor = nil
            range = nil
            cursor = date
        }
    }

    mutating func clear() {
        cursor = nil
        range = nil
        anchor = nil
        sessionActive = false
    }

    /// Put the cursor somewhere without a gesture — how a tapped fact card
    /// moves the instrument to what it is talking about. Whatever was standing
    /// is replaced (a range from an earlier measurement would otherwise survive
    /// under the new cursor), and the next press measures from here.
    mutating func place(at date: Date) {
        cursor = date
        range = nil
        anchor = nil
        sessionActive = false
    }

    // MARK: Private

    /// A while B is being dragged.
    private var anchor: Date?
    /// True between a press and its release, so a continuing drag moves the
    /// current cursor instead of opening a new range.
    private var sessionActive = false

    private mutating func setRange(to date: Date) {
        guard let anchor else { return }
        cursor = nil
        range = min(anchor, date)...max(anchor, date)
    }
}

// MARK: - LabFollowStatus

/// Whether the chart is pinned to the newest reading, and how many readings
/// have landed since it stopped being. Hoisted out of `LabChartView` so the
/// legend can say the same thing the `◂ N NEW` nub does.
enum LabFollowStatus: Equatable {
    case following
    case detached(unseen: Int)

    var isFollowing: Bool {
        self == .following
    }

    var unseen: Int {
        if case .detached(let count) = self { return count }
        return 0
    }
}

// MARK: - LabChartMath

/// Pure geometry and bookkeeping for the lab chart.
enum LabChartMath {
    /// Mirrors `ChartView.Config.zoomLevels` (:614-619).
    static let zoomLabelEvery: [Int: Int] = [3: 1, 6: 2, 12: 3, 24: 4]

    static func chartHeight(available: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        max(minimum, min(maximum, available))
    }

    static func visibleHours(zoomLevel: Int, fallback: Int) -> Int {
        zoomLabelEvery[zoomLevel] == nil ? fallback : zoomLevel
    }

    static func labelEvery(visibleHours: Int) -> Int {
        zoomLabelEvery[visibleHours] ?? 1
    }

    /// The y domain's top is a FLOOR the data can push past — never a ceiling.
    /// `SensorGlucose.glucoseValue` clamps at 501, so a fixed 300 would clip a
    /// real hyper off the chart.
    static func yMax(floor: Double, plotted: [Double]) -> Double {
        max(floor, (plotted.max() ?? 0).rounded(.up))
    }

    /// `chartScrollPosition(x:)` binds the LEADING edge of the visible window.
    static func followEdge(domainStart: Date, domainEnd: Date, visibleDuration: TimeInterval) -> Date {
        max(domainStart, domainEnd.addingTimeInterval(-visibleDuration))
    }

    static func isFollowing(
        scrollPosition: Date,
        domainEnd: Date,
        visibleDuration: TimeInterval,
        slack: TimeInterval
    ) -> Bool {
        scrollPosition >= domainEnd.addingTimeInterval(-visibleDuration - slack)
    }

    /// Readings newer than the newest one the user has already seen.
    ///
    /// Counted by TIMESTAMP on purpose. The store hands the chart a rolling
    /// 24-hour window (`SensorGlucoseStore.swift:328`), so in steady state one
    /// reading enters as one ages out: an array-length delta is zero forever and
    /// the `◂ N NEW` nub would never appear.
    static func unseenCount(readingTimes: [Date], newerThan: Date?) -> Int {
        guard let newerThan else { return 0 }
        return readingTimes.reduce(into: 0) { count, time in
            if time > newerThan { count += 1 }
        }
    }

    /// The smallest gap that counts as a measurement rather than a re-scrub,
    /// expressed as a SCREEN distance so it means the same thing at 3 h and at
    /// 24 h.
    static func minRangeSeconds(visibleDuration: TimeInterval, plotWidth: CGFloat, points: CGFloat) -> TimeInterval {
        let width = max(plotWidth, 1)
        return visibleDuration * TimeInterval(points / width)
    }

    /// A tap that clears the cursors: short, and still. A press-and-hold is the
    /// scrub gesture and must never be mistaken for one (a plain `TapGesture`
    /// would, since SwiftUI taps have no maximum duration).
    static func isClearTap(
        held: TimeInterval,
        translation: CGSize,
        maxDuration: TimeInterval,
        maxDistance: CGFloat
    ) -> Bool {
        held < maxDuration
            && abs(translation.width) <= maxDistance
            && abs(translation.height) <= maxDistance
    }
}

// MARK: - LabDetent

/// The haptic tick as the cursor crosses something worth feeling.
enum LabDetentFeedback: Equatable {
    case light
    case medium
}

enum LabDetent {
    /// Keys for the alarm bounds. Event keys are `meal-`/`insulin-`/`exercise-`
    /// prefixed ids, so they can never collide with these.
    static let lowKey = "low"
    static let highKey = "high"

    /// Returns the haptic for a key change, or nil for none. The caller records
    /// `newKey` as the new previous either way, so leaving and re-entering a
    /// detent ticks again.
    static func feedback(newKey: String?, previousKey: String?, isNight: Bool) -> LabDetentFeedback? {
        guard let newKey, newKey != previousKey else { return nil }
        // Silent through the night profile, mirroring the celebration toast.
        guard !isNight else { return nil }
        return (newKey == lowKey || newKey == highKey) ? .medium : .light
    }
}
