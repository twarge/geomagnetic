// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0
//
// A compact field chart styled after the Apple Health heart-rate chart: a header with the
// latest reading (station in the highlight/accent color), faint vertical hour gridlines
// with hour labels, an unfilled trace, a dot + dashed line at the most recent reading, and
// a y-axis that reads as the deviation (+above / -below) from that line.
//
// Magnetic storms are not drawn on the chart itself; the complication header carries a
// severity-colored warning symbol when the window contains one.
//
// Drawing is split into two layers so accessory complications can tint only the right
// things: the *accent* layer (station code, the data trace + dot, and the y-axis marks)
// gets the watch face's accent color; the *default* layer (gridlines, hour labels, dashed
// reference line, the no-data hatch) renders in the muted default color. In full-color
// contexts (the app and home-screen widgets) both layers draw their own colors as usual.

import SwiftUI
import WidgetKit

/// The compact reading shared by the small complication header and the home-screen widget
/// tiles: "FRD F 50,083.00 nT →". The station and element render in the accent color (and are
/// `widgetAccentable`, so a tinted watch face colors them); the value is the primary color;
/// the unit and trend arrow are the muted secondary color. When `stacked` is set, the station
/// + element sit on a first line and the value + unit + trend on a second — for narrow tiles
/// (the small "2×2" widget) where a single line would be squashed.
struct ObsReadingLine: View {
    /// The slashed chain-link marking a stale/offline reading, shown after the station and
    /// element. (SF Symbols has no "link.slash"; the personal-hotspot glyph is a chain link.)
    static let staleSymbol = "personalhotspot.slash"

    var stationCode: String? = nil
    var element: String? = nil
    var value: Double? = nil
    var unit: String? = nil
    var trend: Double? = nil
    var font: Font = .subheadline
    var stacked: Bool = false
    /// Show the broken-link symbol after the station/element label (stale/offline data).
    var stale: Bool = false

    var body: some View {
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: 1) {
                    label
                    reading
                }
            } else {
                HStack(spacing: 4) {
                    label
                    reading
                }
            }
        }
        .font(font)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    @ViewBuilder private var label: some View {
        HStack(spacing: 4) {
            if let stationCode {
                Text(stationCode).foregroundStyle(Color.accentColor).fontWeight(.semibold).widgetAccentable()
            }
            if let element {
                Text(element).foregroundStyle(Color.accentColor).fontWeight(.semibold).widgetAccentable()
            }
            if stale {
                Image(systemName: Self.staleSymbol)
                    .imageScale(.small)
                    .foregroundStyle(Color.accentColor)
                    .widgetAccentable()
            }
        }
    }

    @ViewBuilder private var reading: some View {
        HStack(spacing: 4) {
            if let value {
                Text(value, format: .number.precision(.fractionLength(2))).foregroundStyle(.primary)
                if let unit { Text(unit).foregroundStyle(.secondary) }
            } else {
                Text("—").foregroundStyle(.primary)
            }
            if let trend {
                Image(systemName: GeomagWidgetView.trendSymbol(trend)).foregroundStyle(.secondary)
            }
        }
    }
}

struct ObsFieldChart: View {
    let series: [ObsLineSeries]
    var stationCode: String? = nil
    var element: String? = nil      // shown after the station code, e.g. "FRD F"
    var latestValue: Double? = nil
    var unit: String? = nil
    var trend: Double? = nil
    var stormIntervals: [StormInterval] = []
    var timeZone: TimeZone = .current
    var showHeader: Bool = true
    var showHourGrid: Bool = true
    var showMinMax: Bool = true
    /// Drop the top/bottom margins so the trace uses the full height (hour labels overlay
    /// the bottom). Used by the small complication to reclaim vertical space.
    var fillsVertically: Bool = false
    var lineWidth: CGFloat = 1.6
    var headerFont: Font = .headline
    /// Break the header onto two lines (station+element / value+unit+trend) for narrow tiles.
    var headerStacked: Bool = false
    /// Mark the header's reading as stale/offline (broken-link symbol after the label).
    var headerStale: Bool = false
    /// The intended time window [start, end] in epoch seconds. When set, the x-axis is anchored
    /// to it (rather than to the data extent), so cached/stale data sits at its true time; any
    /// stretch of the window without data is filled with a subtle diagonal "no data" hatch.
    /// This keeps the watch charts honest when offline instead of stretching stale data to fit.
    var windowStart: Double? = nil
    var windowEnd: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showHeader, stationCode != nil || latestValue != nil {
                headerView
            }
            ZStack {
                Canvas { context, size in drawDefaultLayer(context, size) }
                Canvas { context, size in drawAccentLayer(context, size) }
                    .widgetAccentable()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // The reading line ("FRD F 50083.42 nT →"); station + element accentable (highlight),
    // value primary, unit + arrow muted. In the complication, a storm anywhere in the window
    // appends a severity-colored warning symbol — the app's only storm indicator.
    private var headerView: some View {
        HStack(spacing: 4) {
            ObsReadingLine(stationCode: stationCode, element: element, value: latestValue,
                           unit: unit, trend: trend, font: headerFont, stacked: headerStacked,
                           stale: headerStale)
            if fillsVertically, let worst = stormIntervals.map(\.category).max() {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(headerFont)
                    .foregroundStyle(Self.stormColor(worst))
            }
        }
    }

    // MARK: - Layout

    private struct Geometry {
        let rect: CGRect
        let xRange: ObsPlotRange
        let yRange: ObsPlotRange
        let drawable: [ObsLineSeries]

        func px(_ x: Double) -> CGFloat { rect.minX + rect.width * CGFloat(xRange.unclampedRatio(for: x)) }
        func py(_ y: Double) -> CGFloat { rect.maxY - rect.height * CGFloat(yRange.unclampedRatio(for: y)) }
        func clampX(_ x: CGFloat) -> CGFloat { Swift.min(Swift.max(x, rect.minX), rect.maxX) }
        var referenceY: Double? { drawable.first?.points.last?.y }
    }

    private func geometry(_ size: CGSize) -> Geometry? {
        let drawable = series.filter { $0.points.count >= 2 }
        guard !drawable.isEmpty, size.width > 8, size.height > 8 else { return nil }
        let xs = drawable.flatMap { $0.points.map(\.x) }
        let ys = drawable.flatMap { $0.points.map(\.y) }
        guard let yRange = ObsPlotRange(optionalValues: ys) else { return nil }
        // Anchor to the requested window when given (so stale data keeps its true position);
        // otherwise fall back to the data's own extent.
        let xRange: ObsPlotRange
        if let w0 = windowStart, let w1 = windowEnd, w1 > w0 {
            xRange = ObsPlotRange(minimum: w0, maximum: w1)
        } else if let dataX = ObsPlotRange(optionalValues: xs) {
            xRange = dataX
        } else {
            return nil
        }

        let leftMargin: CGFloat = showMinMax ? 22 : 4
        let hourMargin: CGFloat = fillsVertically ? 0 : (showHourGrid ? 13 : 2)
        let topInset: CGFloat = fillsVertically ? 0 : 2   // else, run up to the header value
        let rect = CGRect(x: leftMargin, y: topInset,
                          width: max(1, size.width - leftMargin - 5),
                          height: max(1, size.height - hourMargin - topInset))
        return Geometry(rect: rect, xRange: xRange, yRange: yRange, drawable: drawable)
    }

    // MARK: - Default layer (muted): gridlines, hour labels, dashed line, storm bands/labels

    private func drawDefaultLayer(_ context: GraphicsContext, _ size: CGSize) {
        guard let g = geometry(size) else { return }
        let rect = g.rect

        for gap in missingIntervals(g) {
            let x0 = g.clampX(g.px(gap.lowerBound))
            let x1 = g.clampX(g.px(gap.upperBound))
            if x1 - x0 > 0.5 {
                ObsPlotHatch.draw(context, in: CGRect(x: x0, y: rect.minY, width: x1 - x0, height: rect.height))
            }
        }

        if showHourGrid {
            for tick in hourTicks(min: g.xRange.minimum, max: g.xRange.maximum) {
                let x = g.px(tick.epoch)
                guard x >= rect.minX - 0.5, x <= rect.maxX + 0.5 else { continue }
                var line = Path()
                line.move(to: CGPoint(x: x, y: rect.minY))
                line.addLine(to: CGPoint(x: x, y: rect.maxY))
                context.stroke(line, with: .color(.secondary.opacity(tick.labeled ? 0.32 : 0.16)),
                               lineWidth: tick.labeled ? 1 : 0.75)
                if let label = tick.label {
                    let point = fillsVertically ? CGPoint(x: x, y: size.height - 1)
                                                : CGPoint(x: x, y: rect.maxY + 2)
                    context.draw(Text(label).font(.system(size: 9)).foregroundStyle(.primary),
                                 at: point, anchor: fillsVertically ? .bottom : .top)
                }
            }
        }

        if let referenceY = g.referenceY {
            let y = g.py(referenceY)
            var dashed = Path()
            dashed.move(to: CGPoint(x: rect.minX, y: y))
            dashed.addLine(to: CGPoint(x: rect.maxX, y: y))
            context.stroke(dashed, with: .color(.secondary.opacity(0.55)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }

    }

    // MARK: - Accent layer (highlight): trace, dot, y-axis marks

    private func drawAccentLayer(_ context: GraphicsContext, _ size: CGSize) {
        guard let g = geometry(size) else { return }
        let rect = g.rect
        let tint = Color.accentColor

        for item in g.drawable {
            var path = Path()
            path.move(to: CGPoint(x: g.px(item.points[0].x), y: g.py(item.points[0].y)))
            for point in item.points.dropFirst() {
                path.addLine(to: CGPoint(x: g.px(point.x), y: g.py(point.y)))
            }
            context.stroke(path, with: .color(tint),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }

        if let last = g.drawable.first?.points.last {
            let center = CGPoint(x: g.px(last.x), y: g.py(last.y))
            let radius = max(2.5, lineWidth + 1.5)
            context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                 width: radius * 2, height: radius * 2)),
                         with: .color(tint))
        }

        if showMinMax, let referenceY = g.referenceY {
            context.draw(Text(Self.signedInt(g.yRange.maximum - referenceY)).font(.system(size: 9)).foregroundStyle(tint),
                         at: CGPoint(x: 2, y: rect.minY), anchor: .topLeading)
            context.draw(Text(Self.signedInt(g.yRange.minimum - referenceY)).font(.system(size: 9)).foregroundStyle(tint),
                         at: CGPoint(x: 2, y: rect.maxY), anchor: .bottomLeading)
        }
    }

    // MARK: - Missing-data hatch

    /// Sub-ranges of the window (epoch seconds) that hold no data (shared math in
    /// ObsPlotHatch; the 40-min floor keeps ordinary data latency from hatching). Empty
    /// unless a window is set, so non-windowed charts are unaffected.
    private func missingIntervals(_ g: Geometry) -> [ClosedRange<Double>] {
        guard let w0 = windowStart, let w1 = windowEnd, w1 > w0 else { return [] }
        let xs = (g.drawable.first?.points.map(\.x) ?? []).sorted()
        return ObsPlotHatch.missingIntervals(sampleTimes: xs, domain: w0...w1)
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
        // Short hour-only labels keep the compact axis from overlapping (e.g. "06" / "6AM").
        formatter.dateFormat = labelStep < 24 ? ObsClock.hourFormat : "M/d"

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
