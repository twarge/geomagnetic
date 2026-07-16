// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0
//
// Interactive line plot, ported from HiDeF's `HDFLinePlotView`. Rendering and the
// pan/zoom/undo machinery are reused; the x-axis now supports a time mode and the y-axis
// labels in fixed units (nanotesla).

import SwiftUI

struct ObsLinePlotView: View {
    let series: [ObsLineSeries]
    let xAxis: ObsXAxisKind
    let xAxisLabel: String
    let yAxisLabel: String

    @Binding var visibleXRange: ObsPlotRange?
    @Binding var visibleYRange: ObsPlotRange?
    /// The full horizontal extent (the loaded window), retained so panning/zooming clamps
    /// to the data the caller fetched rather than the currently visible slice.
    let fullXRange: ObsPlotRange?
    /// Optional wider horizontal clamp for pan/zoom. Letting a pinch-out exceed the loaded
    /// window (into empty margin) is what gives the host a signal to switch to a longer
    /// time range and fetch data that fills the view. nil ⇒ clamp to `fullXRange` as usual.
    let xZoomLimit: ObsPlotRange?

    @State private var dragSelectionRect: CGRect?
    @State private var activeZoomUndoStart: ObsPlotViewport?
    @StateObject private var undoTarget = ObsPlotUndoTarget()

    init(series: [ObsLineSeries],
         xAxis: ObsXAxisKind,
         xAxisLabel: String = "Time",
         yAxisLabel: String,
         visibleXRange: Binding<ObsPlotRange?>,
         visibleYRange: Binding<ObsPlotRange?>,
         fullXRange: ObsPlotRange? = nil,
         xZoomLimit: ObsPlotRange? = nil) {
        self.series = series
        self.xAxis = xAxis
        self.xAxisLabel = xAxisLabel
        self.yAxisLabel = yAxisLabel
        _visibleXRange = visibleXRange
        _visibleYRange = visibleYRange
        self.fullXRange = fullXRange
        self.xZoomLimit = xZoomLimit
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let plotRect = ObsPlotLayout.plotRect(for: size)
            let fullXRange = (self.fullXRange ?? Self.fullXRange(for: series))
            // Pan/zoom clamp horizontally to the (possibly wider) zoom limit; the default
            // view (viewport nil) still shows exactly the loaded window.
            let xClampRange = (xZoomLimit ?? fullXRange)
            let fullYRange = Self.fullYRange(for: series)
            let xRange = (visibleXRange ?? fullXRange).clamped(to: xClampRange)
            let yRange = (visibleYRange ?? fullYRange).clamped(to: fullYRange)

            Canvas { context, canvasSize in
                drawPlot(context: context, size: canvasSize,
                         plotRect: ObsPlotLayout.plotRect(for: canvasSize),
                         xRange: xRange, yRange: yRange, hatchDomain: xClampRange)
            }
            .contentShape(Rectangle())
            .overlay {
                ObsPlotInteractionOverlay(
                    onPan: { translation in
                        pan(translation: translation, plotRect: plotRect,
                            fullXRange: xClampRange, fullYRange: fullYRange)
                    },
                    onZoom: { request in
                        zoom(request, fullXRange: xClampRange, fullYRange: fullYRange)
                    },
                    onContinuousZoomBegan: beginZoomUndoAction,
                    onContinuousZoomEnded: endZoomUndoAction,
                    onReset: resetViewport,
                    onZoomSelectionChanged: { selection in
                        dragSelectionRect = selection?.previewRect(in: plotRect)
                    },
                    onZoomSelectionEnded: { selection in
                        zoom(to: selection, plotRect: plotRect, xRange: xRange, yRange: yRange,
                             fullXRange: xClampRange, fullYRange: fullYRange)
                        dragSelectionRect = nil
                    }
                )
            }
            .overlay { ObsPlotDragSelectionView(rect: dragSelectionRect) }
            .overlay(alignment: .topLeading) {
                if series.count > 1 {
                    ObsPlotLegend(series: series)
                        .padding(.leading, plotRect.minX + 8)
                        .padding(.top, max(2, plotRect.minY - 26))
                        .padding(.trailing, 82)
                        .allowsHitTesting(false)
                }
            }
            #if os(iOS) || os(macOS)
            // Axis-reset buttons, each living in its axis's margin and appearing only once
            // that axis has been zoomed/panned: vertical in the upper-left of the y-axis
            // area, horizontal in the lower-right of the x-axis area.
            .overlay(alignment: .topLeading) {
                if visibleYRange != nil {
                    ObsPlotResetButton(systemImage: "arrow.up.and.down",
                                       help: "Reset Vertical",
                                       action: resetVerticalViewport)
                        .padding(.leading, 4)
                        .padding(.top, plotRect.minY)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if visibleXRange != nil {
                    ObsPlotResetButton(systemImage: "arrow.left.and.right",
                                       help: "Reset Horizontal",
                                       action: resetHorizontalViewport)
                        .padding(.trailing, 16)
                        .padding(.bottom, 2)
                }
            }
            #endif
        }
        .frame(minHeight: 180)
        .onAppear { undoTarget.onRestore = restoreViewport }
        .onDisappear { undoTarget.onRestore = nil }
    }

    // MARK: - Drawing

    private func drawPlot(context: GraphicsContext, size: CGSize, plotRect: CGRect,
                          xRange: ObsPlotRange, yRange: ObsPlotRange, hatchDomain: ObsPlotRange) {
        let drawableSeries = series.filter { $0.points.count >= 2 }
        guard !drawableSeries.isEmpty, size.width > 0, size.height > 0 else { return }

        drawMissingDataHatch(context: context, plotRect: plotRect,
                             xRange: xRange, domain: hatchDomain, series: drawableSeries)
        drawAxes(context: context, size: size, plotRect: plotRect, xRange: xRange, yRange: yRange)

        func point(for plotPoint: ObsPlotPoint) -> CGPoint {
            let xRatio = xRange.unclampedRatio(for: plotPoint.x)
            let yRatio = yRange.unclampedRatio(for: plotPoint.y)
            return CGPoint(x: plotRect.minX + plotRect.width * CGFloat(xRatio),
                           y: plotRect.maxY - plotRect.height * CGFloat(yRatio))
        }

        var clippedContext = context
        clippedContext.clip(to: Path(plotRect))
        for item in drawableSeries {
            let color = ObsPlotSeriesPalette.color(at: item.index)
            var linePath = Path()
            linePath.move(to: point(for: item.points[0]))
            for plotPoint in item.points.dropFirst() {
                linePath.addLine(to: point(for: plotPoint))
            }
            clippedContext.stroke(linePath, with: .color(color), lineWidth: 1.6)

            if item.points.count <= 96 {
                for plotPoint in item.points {
                    let center = point(for: plotPoint)
                    let rect = CGRect(x: center.x - 1.6, y: center.y - 1.6, width: 3.2, height: 3.2)
                    clippedContext.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }
        }
    }

    /// Diagonal stripes over stretches of the pannable domain with no data — a gap in the
    /// record, or a region beyond the loaded window that hasn't been fetched yet (revealed
    /// while pinching out, before the automatic range switch fills it). Coverage is the
    /// union across the drawn series.
    private func drawMissingDataHatch(context: GraphicsContext, plotRect: CGRect,
                                      xRange: ObsPlotRange, domain: ObsPlotRange,
                                      series drawableSeries: [ObsLineSeries]) {
        guard domain.span > 0, plotRect.width > 0 else { return }
        let xs = drawableSeries.flatMap { $0.points.map(\.x) }.sorted()
        for gap in ObsPlotHatch.missingIntervals(sampleTimes: xs, domain: domain.minimum...domain.maximum) {
            let x0 = plotRect.minX + plotRect.width * CGFloat(xRange.unclampedRatio(for: gap.lowerBound))
            let x1 = plotRect.minX + plotRect.width * CGFloat(xRange.unclampedRatio(for: gap.upperBound))
            let clamped0 = min(max(x0, plotRect.minX), plotRect.maxX)
            let clamped1 = min(max(x1, plotRect.minX), plotRect.maxX)
            if clamped1 - clamped0 > 0.5 {
                ObsPlotHatch.draw(context, in: CGRect(x: clamped0, y: plotRect.minY,
                                                      width: clamped1 - clamped0, height: plotRect.height))
            }
        }
    }

    private func drawAxes(context: GraphicsContext, size: CGSize, plotRect: CGRect,
                          xRange: ObsPlotRange, yRange: ObsPlotRange) {
        var gridPath = Path()
        let xAxisDescriptor = ObsAxisDescriptor.makeX(kind: xAxis, range: xRange, tickCount: 5)
        let yTicks = yRange.ticks(count: 5)
        let yDecimals = Self.decimals(forTicks: yTicks)

        for value in yTicks {
            let ratio = CGFloat(yRange.ratio(for: value))
            let y = plotRect.maxY - plotRect.height * ratio
            gridPath.move(to: CGPoint(x: plotRect.minX, y: y))
            gridPath.addLine(to: CGPoint(x: plotRect.maxX, y: y))
            context.draw(
                Text(String(format: "%.\(yDecimals)f", value)).font(.caption).foregroundStyle(.secondary),
                at: CGPoint(x: plotRect.minX - 6, y: y), anchor: .trailing)
        }
        for value in xAxisDescriptor.ticks {
            let ratio = CGFloat(xRange.ratio(for: value))
            let x = plotRect.minX + plotRect.width * ratio
            gridPath.move(to: CGPoint(x: x, y: plotRect.minY))
            gridPath.addLine(to: CGPoint(x: x, y: plotRect.maxY))
            context.draw(
                Text(xAxisDescriptor.label(for: value)).font(.caption).foregroundStyle(.secondary),
                at: CGPoint(x: x, y: plotRect.maxY + 6), anchor: .top)
        }
        context.stroke(gridPath, with: .color(.secondary.opacity(0.18)), lineWidth: 1)

        var axisPath = Path()
        axisPath.move(to: CGPoint(x: plotRect.minX, y: plotRect.minY))
        axisPath.addLine(to: CGPoint(x: plotRect.minX, y: plotRect.maxY))
        axisPath.addLine(to: CGPoint(x: plotRect.maxX, y: plotRect.maxY))
        context.stroke(axisPath, with: .color(.secondary.opacity(0.45)), lineWidth: 1)

        ObsPlotAxisLabelDrawer.drawYAxisLabel(yAxisLabel, context: context, plotRect: plotRect)
        context.draw(
            Text(xAxisLabel).font(.caption.weight(.semibold)).foregroundStyle(.secondary),
            at: CGPoint(x: plotRect.midX, y: size.height - 3), anchor: .bottom)

        if let offsetLabel = xAxisDescriptor.offsetLabel {
            context.draw(
                Text(offsetLabel).font(.caption2).foregroundStyle(.secondary),
                at: CGPoint(x: plotRect.minX, y: size.height - 3), anchor: .bottomLeading)
        }
    }

    private static func decimals(forTicks ticks: [Double]) -> Int {
        guard ticks.count >= 2 else { return 1 }
        let step = abs(ticks[1] - ticks[0])
        guard step.isFinite, step > 0 else { return 1 }
        return min(4, max(0, Int(ceil(-log10(step)))))
    }

    // MARK: - Pan / zoom (ported from HiDeF)

    private func pan(translation: CGSize, plotRect: CGRect,
                     fullXRange: ObsPlotRange, fullYRange: ObsPlotRange) {
        guard plotRect.width > 0, plotRect.height > 0 else { return }
        let xRange = (visibleXRange ?? fullXRange).clamped(to: fullXRange)
        let yRange = (visibleYRange ?? fullYRange).clamped(to: fullYRange)
        let xDelta = -Double(translation.width / plotRect.width) * xRange.span
        let yDelta = Double(translation.height / plotRect.height) * yRange.span
        setViewport(ObsPlotViewport(
            xRange: xRange.shifted(by: xDelta, within: fullXRange),
            yRange: yRange.shifted(by: yDelta, within: fullYRange)))
    }

    private func zoom(_ zoom: ObsPlotZoom, fullXRange: ObsPlotRange, fullYRange: ObsPlotRange) {
        let xRange = (visibleXRange ?? fullXRange).clamped(to: fullXRange)
        let yRange = (visibleYRange ?? fullYRange).clamped(to: fullYRange)
        var nextViewport = currentViewport
        switch zoom.axis {
        case .horizontal:
            nextViewport.xRange = xRange.zoomed(by: Double(zoom.scale), around: 0.5, within: fullXRange)
        case .vertical:
            nextViewport.yRange = yRange.zoomed(by: Double(zoom.scale), around: 0.5, within: fullYRange)
        }
        setViewport(nextViewport)
    }

    private func zoom(to selection: ObsPlotDragSelection, plotRect: CGRect,
                      xRange: ObsPlotRange, yRange: ObsPlotRange,
                      fullXRange: ObsPlotRange, fullYRange: ObsPlotRange) {
        guard let rect = selection.previewRect(in: plotRect),
              plotRect.width > 0, plotRect.height > 0 else { return }
        var nextViewport = currentViewport
        if selection.mode.updatesHorizontal {
            let x0 = Double((rect.minX - plotRect.minX) / plotRect.width)
            let x1 = Double((rect.maxX - plotRect.minX) / plotRect.width)
            nextViewport.xRange = ObsPlotRange(
                minimum: xRange.minimum + (xRange.span * min(x0, x1)),
                maximum: xRange.minimum + (xRange.span * max(x0, x1))).clamped(to: fullXRange)
        }
        if selection.mode.updatesVertical {
            let y0 = Double((plotRect.maxY - rect.maxY) / plotRect.height)
            let y1 = Double((plotRect.maxY - rect.minY) / plotRect.height)
            nextViewport.yRange = ObsPlotRange(
                minimum: yRange.minimum + (yRange.span * min(y0, y1)),
                maximum: yRange.minimum + (yRange.span * max(y0, y1))).clamped(to: fullYRange)
        }
        applyViewport(nextViewport)
    }

    private func resetViewport() {
        applyViewport(ObsPlotViewport(xRange: nil, yRange: nil), actionName: "Reset Plot Zoom")
    }

    private func resetHorizontalViewport() {
        applyViewport(ObsPlotViewport(xRange: nil, yRange: visibleYRange), actionName: "Reset Horizontal Zoom")
    }

    private func resetVerticalViewport() {
        applyViewport(ObsPlotViewport(xRange: visibleXRange, yRange: nil), actionName: "Reset Vertical Zoom")
    }

    private static func fullXRange(for series: [ObsLineSeries]) -> ObsPlotRange {
        ObsPlotRange(values: series.flatMap { $0.points.map(\.x) })
    }

    private static func fullYRange(for series: [ObsLineSeries]) -> ObsPlotRange {
        ObsPlotRange(values: series.flatMap { $0.points.map(\.y) })
    }

    private var currentViewport: ObsPlotViewport {
        ObsPlotViewport(xRange: visibleXRange, yRange: visibleYRange)
    }

    private func setViewport(_ viewport: ObsPlotViewport) {
        visibleXRange = viewport.xRange
        visibleYRange = viewport.yRange
    }

    private func applyViewport(_ viewport: ObsPlotViewport, actionName: String = "Zoom Plot") {
        let previousViewport = currentViewport
        guard previousViewport != viewport else { return }
        registerUndo(to: previousViewport, actionName: actionName)
        setViewport(viewport)
    }

    private func restoreViewport(_ viewport: ObsPlotViewport) { applyViewport(viewport) }

    private func beginZoomUndoAction() {
        if activeZoomUndoStart == nil { activeZoomUndoStart = currentViewport }
    }

    private func endZoomUndoAction() {
        guard let previousViewport = activeZoomUndoStart else { return }
        activeZoomUndoStart = nil
        registerUndo(to: previousViewport, actionName: "Zoom Plot")
    }

    private func registerUndo(to viewport: ObsPlotViewport, actionName: String) {
        guard currentViewport != viewport else { return }
        let undoManager = undoTarget.manager
        undoManager.registerUndo(withTarget: undoTarget) { target in
            target.restore(viewport)
        }
        undoManager.setActionName(actionName)
    }
}
