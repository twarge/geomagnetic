// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0
//
// A compact field chart styled after the Apple Health heart-rate chart: a header with the
// latest reading (station in the highlight/accent color), faint vertical hour gridlines
// with hour labels, an unfilled trace, a dot + dashed line at the most recent reading, and
// a y-axis that reads as the deviation (+above / -below) from that line.
//
// Magnetic-storm sections (fast 30-minute field change) are highlighted with a warning-color
// band and labelled along the bottom.

import SwiftUI

struct ObsFieldChart: View {
    let series: [ObsLineSeries]
    var stationCode: String? = nil
    var latestValue: Double? = nil
    var unit: String? = nil
    var trend: Double? = nil
    var stormIntervals: [StormInterval] = []
    var timeZone: TimeZone = .gmt
    var showHeader: Bool = true
    var showHourGrid: Bool = true
    var showMinMax: Bool = true
    var lineWidth: CGFloat = 1.6
    var headerFont: Font = .headline

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showHeader, let stationCode {
                headerView(stationCode)
            }
            Canvas { context, size in draw(context, size) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // Only the station code is in the highlight/accent color; the value, unit, and trend
    // arrow are the non-highlight color.
    private func headerView(_ code: String) -> some View {
        HStack(spacing: 4) {
            Text(code).foregroundStyle(Color.accentColor).fontWeight(.semibold)
            if let latestValue {
                Text(String(format: "%.2f", latestValue)).foregroundStyle(.primary)
            }
            if let unit {
                Text(unit).foregroundStyle(.secondary)
            }
            if let trend {
                Image(systemName: GeomagWidgetView.trendSymbol(trend)).foregroundStyle(.secondary)
            }
        }
        .font(headerFont)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    // MARK: - Drawing

    private func draw(_ context: GraphicsContext, _ size: CGSize) {
        let drawable = series.filter { $0.points.count >= 2 }
        guard !drawable.isEmpty, size.width > 8, size.height > 8 else { return }
        let xs = drawable.flatMap { $0.points.map(\.x) }
        let ys = drawable.flatMap { $0.points.map(\.y) }
        guard let xRange = ObsPlotRange(optionalValues: xs),
              let yRange = ObsPlotRange(optionalValues: ys) else { return }

        let storms = stormIntervals.filter { $0.category != .quiet && $0.end >= xRange.minimum && $0.start <= xRange.maximum }

        // Integer-only y labels are narrow, so the plot reclaims the saved left margin.
        let leftMargin: CGFloat = showMinMax ? 22 : 4
        let hourMargin: CGFloat = showHourGrid ? 13 : 2
        let stormMargin: CGFloat = storms.isEmpty ? 0 : 12
        // Minimal top inset so the graph runs right up to the value in the header.
        let topInset: CGFloat = 2
        let rect = CGRect(x: leftMargin, y: topInset,
                          width: max(1, size.width - leftMargin - 5),
                          height: max(1, size.height - hourMargin - stormMargin - topInset))
        let tint = Color.accentColor

        func px(_ x: Double) -> CGFloat { rect.minX + rect.width * CGFloat(xRange.unclampedRatio(for: x)) }
        func py(_ y: Double) -> CGFloat { rect.maxY - rect.height * CGFloat(yRange.unclampedRatio(for: y)) }
        func clampX(_ x: CGFloat) -> CGFloat { Swift.min(Swift.max(x, rect.minX), rect.maxX) }

        // Storm sections: warning-color band behind everything.
        for storm in storms {
            let x0 = clampX(px(storm.start))
            let x1 = clampX(px(storm.end))
            let band = CGRect(x: x0, y: rect.minY, width: max(2, x1 - x0), height: rect.height)
            context.fill(Path(band), with: .color(Self.stormColor(storm.category).opacity(0.20)))
        }

        // Faint vertical hour gridlines + hour labels.
        if showHourGrid {
            for tick in hourTicks(min: xRange.minimum, max: xRange.maximum) {
                let x = px(tick.epoch)
                guard x >= rect.minX - 0.5, x <= rect.maxX + 0.5 else { continue }
                var line = Path()
                line.move(to: CGPoint(x: x, y: rect.minY))
                line.addLine(to: CGPoint(x: x, y: rect.maxY))
                context.stroke(line, with: .color(.secondary.opacity(tick.labeled ? 0.32 : 0.16)),
                               lineWidth: tick.labeled ? 1 : 0.75)
                if let label = tick.label {
                    context.draw(Text(label).font(.system(size: 9)).foregroundStyle(.secondary),
                                 at: CGPoint(x: x, y: rect.maxY + 2), anchor: .top)
                }
            }
        }

        // Dashed reference line at the most recent reading.
        let referenceY = drawable.first?.points.last?.y
        if let referenceY {
            let y = py(referenceY)
            var dashed = Path()
            dashed.move(to: CGPoint(x: rect.minX, y: y))
            dashed.addLine(to: CGPoint(x: rect.maxX, y: y))
            context.stroke(dashed, with: .color(.secondary.opacity(0.55)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }

        // Unfilled trace in the accent (highlight) color.
        for item in drawable {
            var path = Path()
            path.move(to: CGPoint(x: px(item.points[0].x), y: py(item.points[0].y)))
            for point in item.points.dropFirst() {
                path.addLine(to: CGPoint(x: px(point.x), y: py(point.y)))
            }
            context.stroke(path, with: .color(tint),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }

        // Dot at the most recent point.
        if let last = drawable.first?.points.last {
            let center = CGPoint(x: px(last.x), y: py(last.y))
            let radius = max(2.5, lineWidth + 1.5)
            context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                 width: radius * 2, height: radius * 2)),
                         with: .color(tint))
        }

        // Y-axis markings: integer deviation from the reference (latest) line.
        if showMinMax, let referenceY {
            context.draw(Text(Self.signedInt(yRange.maximum - referenceY)).font(.system(size: 9)).foregroundStyle(tint),
                         at: CGPoint(x: 2, y: rect.minY), anchor: .topLeading)
            context.draw(Text(Self.signedInt(yRange.minimum - referenceY)).font(.system(size: 9)).foregroundStyle(tint),
                         at: CGPoint(x: 2, y: rect.maxY), anchor: .bottomLeading)
        }

        // Storm category labels along the very bottom, centered under each band.
        for storm in storms {
            let mid = clampX((px(storm.start) + px(storm.end)) / 2)
            context.draw(Text(storm.category.label).font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Self.stormColor(storm.category)),
                         at: CGPoint(x: mid, y: size.height - 2), anchor: .bottom)
        }
    }

    static func signedInt(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return (rounded >= 0 ? "+" : "") + String(rounded)
    }

    static func stormColor(_ category: StormCategory) -> Color {
        switch category {
        case .moderate: return .yellow
        case .intense: return .orange
        case .superStorm: return .red
        case .quiet: return .clear
        }
    }

    private struct HourTick { let epoch: Double; let labeled: Bool; let label: String? }

    /// Hour-aligned gridlines. Gridline spacing keeps the count reasonable; only every
    /// `labelStep`-th line is labelled (hours like "12AM", or dates once spacing ≥ 1 day).
    private func hourTicks(min: Double, max: Double) -> [HourTick] {
        let span = max - min
        guard span > 0 else { return [] }
        let hours = span / 3_600
        let steps: [Double] = [1, 2, 3, 6, 12, 24, 48, 72, 168, 336, 720]
        let gridStep = steps.first { hours / $0 <= 30 } ?? 720
        let labelStep = steps.first { $0 >= gridStep && hours / $0 <= 5 } ?? gridStep
        let offsetHours = Double(timeZone.secondsFromGMT()) / 3_600

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = labelStep < 24 ? "ha" : "M/d"

        let endLocalHour = max / 3_600 + offsetHours
        var localHour = ((min / 3_600 + offsetHours) / gridStep).rounded(.up) * gridStep
        var ticks: [HourTick] = []
        let labelStepInt = Int(labelStep)
        while localHour <= endLocalHour + 0.001, ticks.count < 200 {
            let epoch = (localHour - offsetHours) * 3_600
            let labeled = labelStepInt > 0 && Int(localHour.rounded()) % labelStepInt == 0
            let label = labeled ? formatter.string(from: Date(timeIntervalSince1970: epoch)) : nil
            ticks.append(HourTick(epoch: epoch, labeled: labeled, label: label))
            localHour += gridStep
        }
        return ticks
    }
}
