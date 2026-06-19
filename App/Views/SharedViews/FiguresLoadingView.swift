//
//  FiguresLoadingView.swift
//  DOSBTS
//
//  Claude.ai-style pulsing dots in the DOS amber phosphor vocabulary.
//  Uses TimelineView + Canvas for frame-rate-independent animation.
//  Reduce-motion: renders static dots at fixed opacity.
//

import SwiftUI

/// Three pulsing amber dots — used wherever the app awaits an async result
/// (Claude API, sensor connecting).
struct FiguresLoadingView: View {
    /// How often the pulse redraws.
    /// - `.smooth` is display-linked (up to 120 Hz) for short-lived waits
    ///   (Claude analysis, digest load) where the buttery pulse is worth it.
    /// - `.lowPower` redraws ~10×/s for long-lived states — sensor warmup can
    ///   sit in `.transient` for up to ~60 min, and a continuous full-rate
    ///   `TimelineView(.animation)` render loop there is a needless battery drain.
    enum Cadence {
        case smooth
        case lowPower
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var dotSize: CGFloat = 8
    var spacing: CGFloat = 6
    var color: Color = AmberTheme.amber
    var cadence: Cadence = .smooth

    private let dotCount = 3
    private let lowPowerInterval: TimeInterval = 0.1   // ~10 fps

    var body: some View {
        Group {
            if reduceMotion {
                staticDots
            } else if cadence == .lowPower {
                TimelineView(.periodic(from: Date(), by: lowPowerInterval)) { timeline in
                    dotsCanvas(at: timeline.date)
                }
            } else {
                TimelineView(.animation) { timeline in
                    dotsCanvas(at: timeline.date)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Shared pulse drawing for both schedules — only the redraw cadence differs.
    private func dotsCanvas(at date: Date) -> some View {
        Canvas { context, size in
            let elapsed = date.timeIntervalSinceReferenceDate
            let totalWidth = size.width
            let step = totalWidth / CGFloat(dotCount)

            for i in 0 ..< dotCount {
                // Stagger each dot by 0.35 s so they wave sequentially.
                let phase = (elapsed - Double(i) * 0.35) * 2.2
                // sin oscillates −1…1; map to 0.4…1.0 opacity and 0.6…1.0 scale.
                let t = (sin(phase * .pi) + 1) / 2   // 0…1
                let scale = 0.6 + 0.4 * t
                let opacity = 0.35 + 0.65 * t

                let cx = step * (CGFloat(i) + 0.5)
                let cy = size.height / 2
                let r = dotSize / 2 * scale
                let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                context.opacity = opacity
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }
        }
        .frame(
            width: CGFloat(dotCount) * dotSize + CGFloat(dotCount - 1) * spacing,
            height: dotSize * 2
        )
    }

    private var staticDots: some View {
        HStack(spacing: spacing) {
            ForEach(0 ..< dotCount, id: \.self) { _ in
                Circle()
                    .fill(color.opacity(0.6))
                    .frame(width: dotSize, height: dotSize)
            }
        }
        .frame(height: dotSize * 2)
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 24) {
        FiguresLoadingView()
        FiguresLoadingView(dotSize: 12, spacing: 8)
        FiguresLoadingView(dotSize: 6, spacing: 4, color: AmberTheme.cgaCyan)
    }
    .padding()
    .background(AmberTheme.dosBlack)
}
#endif
