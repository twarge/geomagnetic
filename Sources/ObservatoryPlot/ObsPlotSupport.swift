// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0
//
// Small plot chrome (layout math, legend, reset controls, drag-selection overlay),
// ported from HiDeF.

import SwiftUI

enum ObsPlotLayout {
    static func plotRect(for size: CGSize) -> CGRect {
        let leftMargin = min(112, max(72, size.width * 0.18))
        let topMargin: CGFloat = size.height < 200 ? 28 : 56
        let bottomMargin = min(74, max(48, size.height * 0.18))
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

struct ObsPlotResetControls: View {
    let onResetHorizontal: () -> Void
    let onResetVertical: () -> Void

    var body: some View {
        HStack(spacing: Self.spacing) {
            Button(action: onResetHorizontal) {
                Image(systemName: "arrow.left.and.right")
                    .frame(width: Self.tapTarget, height: Self.tapTarget)
                    .contentShape(Rectangle())
            }
            .help("Reset Horizontal")

            Button(action: onResetVertical) {
                Image(systemName: "arrow.up.and.down")
                    .frame(width: Self.tapTarget, height: Self.tapTarget)
                    .contentShape(Rectangle())
            }
            .help("Reset Vertical")
        }
        .buttonStyle(.borderless)
        .controlSize(.regular)
        .font(Self.iconFont)
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, Self.verticalPadding)
        .background(.regularMaterial, in: Capsule())
    }

    #if os(iOS)
    private static let iconFont: Font = .title3
    private static let tapTarget: CGFloat? = 40
    private static let spacing: CGFloat = 8
    private static let horizontalPadding: CGFloat = 8
    private static let verticalPadding: CGFloat = 4
    #else
    private static let iconFont: Font = .body
    private static let tapTarget: CGFloat? = nil
    private static let spacing: CGFloat = 4
    private static let horizontalPadding: CGFloat = 7
    private static let verticalPadding: CGFloat = 5
    #endif
}

/// Private undo for plot zoom/pan so it never marks anything "edited" (ported from HiDeF).
@MainActor
final class ObsPlotUndoTarget: ObservableObject {
    let manager = UndoManager()
    var onRestore: ((ObsPlotViewport) -> Void)?

    func restore(_ viewport: ObsPlotViewport) { onRestore?(viewport) }
}
