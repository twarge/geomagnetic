// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WidgetKit

/// A minimal, non-interactive line chart for tight spaces: widgets, the watch face
/// complications, and watch glances. No axes, no gestures — just the trace(s), optionally
/// with a dot at the most recent sample and a dashed line at its level.
struct ObsSparkline: View {
    let series: [ObsLineSeries]
    var lineWidth: CGFloat = 2
    var showsLatestDot: Bool = true
    /// A dashed horizontal line across the plot at the most recent sample's level, as the
    /// field chart draws — in the muted default layer, never accented.
    var showsLatestLine: Bool = false
    var tint: Color? = nil
    var fill: Bool = false
    /// The intended time window in epoch seconds. When set, the x-axis is anchored to it
    /// rather than to the data, so stale data sits at its true time and the stretch of the
    /// window without data is hatched, as in the field chart. nil ⇒ fit to the data.
    var window: ClosedRange<Double>? = nil
    /// Puts the trace (not the hatch) in the accent group, so a tinted watch face colors
    /// only the data — the field chart's layering.
    var accentsTrace: Bool = false

    var body: some View {
        ZStack {
            if window != nil || showsLatestLine {
                Canvas { context, size in
                    drawHatch(context, size)
                    drawLatestLine(context, size)
                }
            }
            Canvas { context, size in drawTrace(context, size) }
                .widgetAccentable(accentsTrace)
        }
    }

    private struct Layout {
        let rect: CGRect
        let xRange: ObsPlotRange
        let yRange: ObsPlotRange?
        let drawable: [ObsLineSeries]

        func point(_ p: ObsPlotPoint, yRange: ObsPlotRange) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * CGFloat(xRange.unclampedRatio(for: p.x)),
                    y: rect.maxY - rect.height * CGFloat(yRange.unclampedRatio(for: p.y)))
        }
    }

    private func layout(_ size: CGSize) -> Layout? {
        guard size.width > 1, size.height > 1 else { return nil }
        let drawable = series.filter { $0.points.count >= 2 }
        let xRange = window.map { ObsPlotRange(minimum: $0.lowerBound, maximum: $0.upperBound) }
            ?? ObsPlotRange(optionalValues: drawable.flatMap { $0.points.map(\.x) })
        guard let xRange else { return nil }
        let inset = lineWidth + 1
        let rect = CGRect(x: inset, y: inset,
                          width: max(1, size.width - inset * 2),
                          height: max(1, size.height - inset * 2))
        let yRange = ObsPlotRange(optionalValues: drawable.flatMap { $0.points.map(\.y) })
        return Layout(rect: rect, xRange: xRange, yRange: yRange, drawable: drawable)
    }

    private func drawHatch(_ context: GraphicsContext, _ size: CGSize) {
        guard let window, let layout = layout(size) else { return }
        let rect = layout.rect
        let xs = (layout.drawable.first?.points.map(\.x) ?? []).sorted()
        func px(_ x: Double) -> CGFloat {
            let x = rect.minX + rect.width * CGFloat(layout.xRange.unclampedRatio(for: x))
            return min(max(x, rect.minX), rect.maxX)
        }
        for gap in ObsPlotHatch.missingIntervals(sampleTimes: xs, domain: window) {
            let x0 = px(gap.lowerBound), x1 = px(gap.upperBound)
            if x1 - x0 > 0.5 {
                ObsPlotHatch.draw(context, in: CGRect(x: x0, y: rect.minY, width: x1 - x0, height: rect.height))
            }
        }
    }

    /// The reference line at the level of the sample the latest dot marks.
    private func drawLatestLine(_ context: GraphicsContext, _ size: CGSize) {
        guard showsLatestLine, let layout = layout(size), let yRange = layout.yRange,
              let last = layout.drawable.last?.points.last else { return }
        let y = layout.point(last, yRange: yRange).y
        var line = Path()
        line.move(to: CGPoint(x: layout.rect.minX, y: y))
        line.addLine(to: CGPoint(x: layout.rect.maxX, y: y))
        context.stroke(line, with: .color(Color.secondary.opacity(0.55)),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
    }

    private func drawTrace(_ context: GraphicsContext, _ size: CGSize) {
        guard let layout = layout(size), !layout.drawable.isEmpty, let yRange = layout.yRange
        else { return }
        let rect = layout.rect

        func point(_ p: ObsPlotPoint) -> CGPoint { layout.point(p, yRange: yRange) }

        for (offset, item) in layout.drawable.enumerated() {
            let color = tint ?? ObsPlotSeriesPalette.color(at: item.index)
            var path = Path()
            path.move(to: point(item.points[0]))
            for p in item.points.dropFirst() { path.addLine(to: point(p)) }

            if fill, layout.drawable.count == 1 {
                var area = path
                area.addLine(to: CGPoint(x: point(item.points.last!).x, y: rect.maxY))
                area.addLine(to: CGPoint(x: point(item.points[0]).x, y: rect.maxY))
                area.closeSubpath()
                context.fill(area, with: .color(color.opacity(0.18)))
            }

            context.stroke(path, with: .color(color),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

            if showsLatestDot, offset == layout.drawable.count - 1, let last = item.points.last {
                let center = point(last)
                let dot = CGRect(x: center.x - lineWidth, y: center.y - lineWidth,
                                 width: lineWidth * 2, height: lineWidth * 2)
                context.fill(Path(ellipseIn: dot), with: .color(color))
            }
        }
    }
}
