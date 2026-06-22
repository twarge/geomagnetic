// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// A minimal, non-interactive line chart for tight spaces: widgets, the watch face
/// complications, and watch glances. No axes, no gestures — just the trace(s), optionally
/// with a dot at the most recent sample.
struct ObsSparkline: View {
    let series: [ObsLineSeries]
    var lineWidth: CGFloat = 2
    var showsLatestDot: Bool = true
    var tint: Color? = nil
    var fill: Bool = false

    var body: some View {
        Canvas { context, size in
            let drawable = series.filter { $0.points.count >= 2 }
            guard !drawable.isEmpty, size.width > 1, size.height > 1 else { return }

            let xs = drawable.flatMap { $0.points.map(\.x) }
            let ys = drawable.flatMap { $0.points.map(\.y) }
            guard let xRange = ObsPlotRange(optionalValues: xs),
                  let yRange = ObsPlotRange(optionalValues: ys) else { return }

            let inset = lineWidth + 1
            let rect = CGRect(x: inset, y: inset,
                              width: max(1, size.width - inset * 2),
                              height: max(1, size.height - inset * 2))

            func point(_ p: ObsPlotPoint) -> CGPoint {
                CGPoint(x: rect.minX + rect.width * CGFloat(xRange.unclampedRatio(for: p.x)),
                        y: rect.maxY - rect.height * CGFloat(yRange.unclampedRatio(for: p.y)))
            }

            for (offset, item) in drawable.enumerated() {
                let color = tint ?? ObsPlotSeriesPalette.color(at: item.index)
                var path = Path()
                path.move(to: point(item.points[0]))
                for p in item.points.dropFirst() { path.addLine(to: point(p)) }

                if fill, drawable.count == 1 {
                    var area = path
                    area.addLine(to: CGPoint(x: point(item.points.last!).x, y: rect.maxY))
                    area.addLine(to: CGPoint(x: point(item.points[0]).x, y: rect.maxY))
                    area.closeSubpath()
                    context.fill(area, with: .color(color.opacity(0.18)))
                }

                context.stroke(path, with: .color(color),
                               style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

                if showsLatestDot, offset == drawable.count - 1, let last = item.points.last {
                    let center = point(last)
                    let dot = CGRect(x: center.x - lineWidth, y: center.y - lineWidth,
                                     width: lineWidth * 2, height: lineWidth * 2)
                    context.fill(Path(ellipseIn: dot), with: .color(color))
                }
            }
        }
    }
}
