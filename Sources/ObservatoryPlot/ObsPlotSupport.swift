// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0
//
// Small plot chrome (layout math, legend, reset controls, drag-selection overlay),
// ported from HiDeF.

import SwiftUI

/// The subtle diagonal-stripe fill marking a stretch of a chart with no data (a gap in the
/// record, or a region not fetched yet). Shared by the compact field chart and the
/// interactive plot so "no data" reads the same everywhere.
enum ObsPlotHatch {
    static func draw(_ context: GraphicsContext, in rect: CGRect) {
        context.drawLayer { layer in
            layer.clip(to: Path(rect))
            layer.fill(Path(rect), with: .color(.secondary.opacity(0.06)))
            var lines = Path()
            var x = rect.minX - rect.height
            while x < rect.maxX {
                lines.move(to: CGPoint(x: x, y: rect.maxY))
                lines.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
                x += 6
            }
            layer.stroke(lines, with: .color(.secondary.opacity(0.22)), lineWidth: 0.75)
        }
    }

    /// Sub-ranges of `domain` with no data, given the union of sample times across the
    /// visible series. Interior gaps must beat several times the typical spacing (decimated
    /// series have irregular spacing that must not hatch). The domain's *edges* use only the
    /// fixed floor: the decimator always preserves the true first/last samples, so a leading
    /// or trailing gap — e.g. stale data ending hours before "now" while offline — is real
    /// no matter how coarse the decimation.
    static func missingIntervals(sampleTimes xs: [Double], domain: ClosedRange<Double>,
                                 minimumGap: Double = 2_400) -> [ClosedRange<Double>] {
        guard domain.upperBound > domain.lowerBound else { return [] }
        guard xs.count >= 2 else { return [domain] }
        var deltas: [Double] = []
        deltas.reserveCapacity(xs.count - 1)
        for i in 1..<xs.count { deltas.append(xs[i] - xs[i - 1]) }
        let typical = deltas.sorted()[deltas.count / 2]
        let interiorThreshold = max(typical * 4, minimumGap)
        var gaps: [ClosedRange<Double>] = []
        if let first = xs.first, first - domain.lowerBound > minimumGap {
            gaps.append(domain.lowerBound...first)
        }
        for i in 1..<xs.count where xs[i] - xs[i - 1] > interiorThreshold {
            gaps.append(xs[i - 1]...xs[i])
        }
        if let last = xs.last, domain.upperBound - last > minimumGap {
            gaps.append(last...domain.upperBound)
        }
        return gaps
    }
}

enum ObsPlotLayout {
    static func plotRect(for size: CGSize) -> CGRect {
        let leftMargin = min(112, max(72, size.width * 0.18))
        // Just enough headroom for the topmost y tick label…
        let topMargin: CGFloat = 14
        // …and below: tick labels (~21pt) + the axis title (~18pt) with a small gap.
        let bottomMargin: CGFloat = 44
        return CGRect(
            x: leftMargin,
            y: topMargin,
            width: max(1, size.width - leftMargin - 20),
            height: max(1, size.height - bottomMargin - topMargin)
        )
    }
}

enum ObsPlotAxisLabelDrawer {
    static func drawYAxisLabel(_ label: String, context: GraphicsContext, plotRect: CGRect) {
        var labelContext = context
        labelContext.translateBy(x: max(16, plotRect.minX - 60), y: plotRect.midY)
        labelContext.rotate(by: .degrees(-90))
        labelContext.draw(
            Text(label).font(.callout.weight(.semibold)).foregroundStyle(.secondary),
            at: .zero, anchor: .center)
    }
}

struct ObsPlotDragSelectionView: View {
    let rect: CGRect?

    var body: some View {
        Canvas { context, _ in
            guard let rect, rect.width > 0, rect.height > 0 else { return }
            let path = Path(rect)
            context.fill(path, with: .color(.accentColor.opacity(0.14)))
            context.stroke(path, with: .color(.accentColor.opacity(0.9)),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .allowsHitTesting(false)
    }
}

struct ObsPlotLegend: View {
    let series: [ObsLineSeries]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(series) { item in
                HStack(spacing: 5) {
                    Circle()
                        .fill(ObsPlotSeriesPalette.color(at: item.index))
                        .frame(width: 7, height: 7)
                    Text(item.label)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: 150, alignment: .leading)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Plot legend")
    }
}

/// A single axis-reset button, shown in the axis margin only while that axis is zoomed
/// or panned away from the full view.
struct ObsPlotResetButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: Self.tapTarget, height: Self.tapTarget)
                .contentShape(Circle())
        }
        .help(help)
        .accessibilityLabel(help)
        .buttonStyle(.borderless)
        .controlSize(.regular)
        .font(Self.iconFont)
        .background(.regularMaterial, in: Circle())
    }

    #if os(iOS)
    private static let iconFont: Font = .body
    private static let tapTarget: CGFloat? = 36
    #else
    private static let iconFont: Font = .callout
    private static let tapTarget: CGFloat? = 26
    #endif
}

/// Private undo for plot zoom/pan so it never marks anything "edited" (ported from HiDeF).
@MainActor
final class ObsPlotUndoTarget: ObservableObject {
    let manager = UndoManager()
    var onRestore: ((ObsPlotViewport) -> Void)?

    func restore(_ viewport: ObsPlotViewport) { onRestore?(viewport) }
}
