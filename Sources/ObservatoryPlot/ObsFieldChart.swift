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

/// The shared data-update transition. WidgetKit caps entry-transition animations at two
/// seconds — use all of it, eased both ways.
enum ObsScrollTransition {
    static let duration: Double = 2
    static var animation: Animation { .easeInOut(duration: duration) }
    /// Seconds between the pre-scroll and scrolled entries of a timeline pair. The home
    /// screen switches entries at roughly minute granularity, so anything shorter risks
    /// the pair collapsing into one un-animated jump.
    static let phaseGap: TimeInterval = 60
}

/// The compact reading shared by the small complication header and the home-screen widget
/// tiles: "FRD F 50,083.00 nT →". The station and element render in the accent color (and are
/// `widgetAccentable`, so a tinted watch face colors them); the value is the primary color;
/// the unit and trend arrow are the muted secondary color. When `stacked` is set, the station
/// + element sit on a first line and the value + unit + trend on a second — for narrow tiles
/// (the small "2×2" widget) where a single line would be squashed.
struct ObsReadingLine: View {
    var stationCode: String? = nil
    var element: String? = nil
    var value: Double? = nil
    var unit: String? = nil
    var trend: Double? = nil
    var font: Font = .subheadline
    var stacked: Bool = false
    /// Stale badge shown after the station/element label: a broken link when the mirror is
    /// unreachable, a late clock when the source is behind. nil ⇒ fresh, no badge.
    var staleSymbol: String? = nil

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
            if let staleSymbol {
                Image(systemName: staleSymbol)
                    .imageScale(.small)
                    .foregroundStyle(Color.accentColor)
                    .widgetAccentable()
            }
        }
    }

    @ViewBuilder private var reading: some View {
        HStack(spacing: 4) {
            if let value {
                Text(value, format: .number.precision(.fractionLength(2)))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText(value: value))
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
    /// Stale badge for the header's reading (see ObsReadingLine.staleSymbol). nil ⇒ fresh.
    var headerStaleSymbol: String? = nil
    /// The intended time window [start, end] in epoch seconds. When set, the x-axis is anchored
    /// to it (rather than to the data extent), so cached/stale data sits at its true time; any
    /// stretch of the window without data is filled with a subtle diagonal "no data" hatch.
    /// This keeps the watch charts honest when offline instead of stretching stale data to fit.
    var windowStart: Double? = nil
    var windowEnd: Double? = nil
    /// Extra seconds of data drawn (off-screen) to the left of the window. The two entries
    /// of an animated widget refresh share one drawing that is this much wider than the
    /// window; only the horizontal shift differs between them, which WidgetKit animates —
    /// the new stretch scrolls in from the right. Requires an anchored window.
    var scrollbackSeconds: Double = 0
    /// When set (the pre-scroll entry of a pair), the chart displays the window slid back
    /// to end here — what the previous timeline showed — instead of at `windowEnd`.
    var displayWindowEnd: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showHeader, stationCode != nil || latestValue != nil {
                headerView
            }
            GeometryReader { proxy in
                chartArea(size: proxy.size)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func chartArea(size: CGSize) -> some View {
        if let g = geometry(size, window: visibleXRange) {
            ZStack(alignment: .topLeading) {
                scrollingLayers(g, size: size)
                decorations(g, size: size)
            }
            .animation(ObsScrollTransition.animation, value: effectiveDisplayEnd ?? 0)
        }
    }

    // The reading line ("FRD F 50083.42 nT →"); station + element accentable (highlight),
    // value primary, unit + arrow muted. In the complication, a storm anywhere in the window
    // appends a severity-colored warning symbol — the app's only storm indicator.
    private var headerView: some View {
        HStack(spacing: 4) {
            ObsReadingLine(stationCode: stationCode, element: element, value: latestValue,
                           unit: unit, trend: trend, font: headerFont, stacked: headerStacked,
                           staleSymbol: headerStaleSymbol)
            if fillsVertically, let worst = stormIntervals.map(\.category).max() {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(headerFont)
                    .foregroundStyle(Self.stormColor(worst))
            }
        }
    }

    // MARK: - Scroll transition state

    /// The anchored window, when one is set (scrolling needs a time anchor).
    private var windowRange: ObsPlotRange? {
        guard let w0 = windowStart, let w1 = windowEnd, w1 > w0 else { return nil }
        return ObsPlotRange(minimum: w0, maximum: w1)
    }

    private var activeScrollback: Double {
        windowRange != nil && scrollbackSeconds > 0 ? scrollbackSeconds : 0
    }

    /// End of the window actually shown: the pre-scroll entry sits at the previous
    /// refresh's end; the scrolled entry (displayWindowEnd nil) at the window's own end.
    private var effectiveDisplayEnd: Double? {
        guard let window = windowRange else { return nil }
        guard activeScrollback > 0, let display = displayWindowEnd else { return window.maximum }
        return min(max(display, window.minimum), window.maximum)
    }

    /// The visible axis: the window slid back to the displayed end (identical to the
    /// window itself outside a scroll transition).
    private var visibleXRange: ObsPlotRange? {
        guard let window = windowRange, let end = effectiveDisplayEnd else { return nil }
        return ObsPlotRange(minimum: end - window.span, maximum: end)
    }

    /// The domain the scrolling canvases draw: the window plus the scrollback stretch, so
    /// both entries of a pair share one identical drawing and only the offset differs.
    private var drawingXRange: ObsPlotRange? {
        guard let window = windowRange else { return nil }
        return ObsPlotRange(minimum: window.minimum - activeScrollback, maximum: window.maximum)
    }

    /// Trace point the dashed reference line, dot, and ± labels describe: the newest
    /// reading at or before the displayed window end.
    private var referencePoint: ObsPlotPoint? {
        guard let points = series.first(where: { $0.points.count >= 2 })?.points else { return nil }
        guard activeScrollback > 0, let end = effectiveDisplayEnd else { return points.last }
        return points.last(where: { $0.x <= end }) ?? points.last
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
    }

    private func geometry(_ size: CGSize, window: ObsPlotRange?) -> Geometry? {
        let drawable = series.filter { $0.points.count >= 2 }
        guard !drawable.isEmpty, size.width > 8, size.height > 8 else { return nil }
        let ys = drawable.flatMap { $0.points.map(\.y) }
        guard let yRange = ObsPlotRange(optionalValues: ys) else { return nil }
        // Anchor to the requested window when given (so stale data keeps its true position);
        // otherwise fall back to the data's own extent.
        let xRange: ObsPlotRange
        if let window {
            xRange = window
        } else if let dataX = ObsPlotRange(optionalValues: drawable.flatMap { $0.points.map(\.x) }) {
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

    // MARK: - Scrolling and static layers

    /// The time-anchored drawing (trace, gridlines, hour labels, hatch) on a canvas wide
    /// enough to hold the scrollback stretch, shifted so the displayed window fills the
    /// plot area and masked so nothing bleeds into the y-label gutter. Between the two
    /// entries of a scroll pair only the shift changes — the animatable part.
    private func scrollingLayers(_ g: Geometry, size: CGSize) -> some View {
        let plotWidth = g.rect.width
        var canvasWidth = size.width
        var shift: CGFloat = 0
        if activeScrollback > 0, let window = windowRange, let end = effectiveDisplayEnd {
            let drawnSpan = window.span + activeScrollback
            let drawnPlotWidth = plotWidth * CGFloat(drawnSpan / window.span)
            canvasWidth = size.width + (drawnPlotWidth - plotWidth)
            let endRatio = (end - (window.minimum - activeScrollback)) / drawnSpan
            shift = plotWidth - drawnPlotWidth * CGFloat(endRatio)
        }
        return ZStack {
            Canvas { context, canvasSize in drawDefaultLayer(context, canvasSize) }
            Canvas { context, canvasSize in drawAccentLayer(context, canvasSize) }
                .widgetAccentable()
        }
        .frame(width: canvasWidth, height: size.height)
        .offset(x: shift)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .mask(alignment: .topLeading) { Rectangle().padding(.leading, g.rect.minX) }
    }

    /// The reading-anchored chrome, as SwiftUI views so a scroll pair animates them: the
    /// dashed reference line slides to the new reading's level, the ± range labels roll,
    /// and the latest-reading dot glides to the incoming point.
    @ViewBuilder
    private func decorations(_ g: Geometry, size: CGSize) -> some View {
        if let reference = referencePoint {
            ObsHorizontalLine()
                .stroke(Color.secondary.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(height: 1)
                .padding(.leading, g.rect.minX)
                .padding(.trailing, size.width - g.rect.maxX)
                .offset(y: g.py(reference.y) - 0.5)

            let radius = max(2.5, lineWidth + 1.5)
            Circle()
                .fill(Color.accentColor)
                .frame(width: radius * 2, height: radius * 2)
                .offset(x: g.px(reference.x) - radius, y: g.py(reference.y) - radius)
                .widgetAccentable()

            if showMinMax {
                deviationLabel(g.yRange.maximum - reference.y)
                    .padding(EdgeInsets(top: g.rect.minY, leading: 2, bottom: 0, trailing: 0))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                deviationLabel(g.yRange.minimum - reference.y)
                    .padding(EdgeInsets(top: 0, leading: 2, bottom: size.height - g.rect.maxY, trailing: 0))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
    }

    private func deviationLabel(_ delta: Double) -> some View {
        Text(Self.signedInt(delta))
            .font(.system(size: 9))
            .foregroundStyle(Color.accentColor)
            .contentTransition(.numericText(value: delta))
            .widgetAccentable()
    }

    // MARK: - Default layer (muted): gridlines, hour labels, no-data hatch

    private func drawDefaultLayer(_ context: GraphicsContext, _ size: CGSize) {
        guard let g = geometry(size, window: drawingXRange) else { return }
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

    }

    // MARK: - Accent layer (highlight): the data trace

    private func drawAccentLayer(_ context: GraphicsContext, _ size: CGSize) {
        guard let g = geometry(size, window: drawingXRange) else { return }
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
    }

    // MARK: - Missing-data hatch

    /// Sub-ranges of the drawn domain (the window plus any scrollback stretch, epoch
    /// seconds) that hold no data (shared math in ObsPlotHatch; the 40-min floor keeps
    /// ordinary data latency from hatching). Empty unless a window is set, so non-windowed
    /// charts are unaffected.
    private func missingIntervals(_ g: Geometry) -> [ClosedRange<Double>] {
        guard let domain = drawingXRange else { return [] }
        let xs = (g.drawable.first?.points.map(\.x) ?? []).sorted()
        return ObsPlotHatch.missingIntervals(sampleTimes: xs, domain: domain.minimum...domain.maximum)
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

/// A single horizontal line through the middle of its rect (dashed via the stroke style).
private struct ObsHorizontalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
