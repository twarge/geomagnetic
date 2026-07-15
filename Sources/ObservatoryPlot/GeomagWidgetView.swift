// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0
//
// One adaptive view for every WidgetKit family — iOS/macOS home-screen widgets, iOS lock
// screen accessories, and watch complications — driven by a GeomagWidgetSnapshot. The
// `style` selects which member of the widget/complication set is being rendered.

import SwiftUI
import WidgetKit

enum GeomagWidgetStyle {
    case field        // headline value + sparkline
    case chart        // sparkline-dominant
}

struct GeomagWidgetView: View {
    let snapshot: GeomagWidgetSnapshot
    var style: GeomagWidgetStyle = .field
    /// When the host disables content margins, re-apply them on every side but the top so
    /// the header sits flush with the top edge (used by the complication).
    var dropsTopMargin: Bool = false
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var contentMargins

    var body: some View {
        content
            .padding(dropsTopMargin
                     ? EdgeInsets(top: 0, leading: contentMargins.leading,
                                  bottom: contentMargins.bottom, trailing: contentMargins.trailing)
                     : EdgeInsets())
            .containerBackground(for: .widget) { background }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            inlineLabel
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangularChart
        default:
            #if os(watchOS)
            if family == .accessoryCorner {
                corner
            } else {
                circular
            }
            #else
            systemTile
            #endif
        }
    }

    // MARK: - Accessory families

    /// "FRD F" (plus the broken-link symbol when the reading is stale/offline) as a single
    /// Text, so it stays one line and inherits the accent styling wherever it's used.
    private var stationElementLabel: Text {
        let station = "\(snapshot.observatoryCode) \(snapshot.primaryElement?.code ?? "")"
        guard snapshot.isStale else { return Text(station) }
        return Text("\(station) \(Image(systemName: ObsReadingLine.staleSymbol))")
    }

    private var inlineLabel: Text {
        let station = "\(snapshot.observatoryCode) \(snapshot.primaryElement?.code ?? "")"
        let reading = snapshot.primaryValue.map {
            "\(Self.compact($0)) \(snapshot.primaryElement?.unit ?? "nT")"
        } ?? "—"
        guard snapshot.isStale else { return Text("\(station) \(reading)") }
        return Text("\(station) \(Image(systemName: ObsReadingLine.staleSymbol)) \(reading)")
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                stationElementLabel
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .widgetAccentable()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                // The full 5-digit reading in nT, no decimals — always the latest measurement.
                Text(snapshot.primaryValue.map { String(Int($0.rounded())) } ?? "—")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
            }
            .padding(.horizontal, 1)
        }
    }

    // The largest accessory family — the watch rectangular complication and the iOS
    // lock-screen rectangular — uses the same chart style as the watch app.
    @ViewBuilder
    private var rectangularChart: some View {
        if snapshot.sparkline.isEmpty {
            HStack(spacing: 4) {
                ObsReadingLine(stationCode: snapshot.observatoryCode,
                               element: snapshot.primaryElement?.code,
                               value: snapshot.primaryValue,
                               unit: snapshot.primaryElement?.unit,
                               font: .footnote,
                               stale: snapshot.isStale)
                Spacer(minLength: 0)
            }
        } else {
            ObsFieldChart(series: snapshot.sparkline,
                          stationCode: snapshot.observatoryCode,
                          element: snapshot.primaryElement?.code,
                          latestValue: snapshot.primaryValue,
                          unit: snapshot.primaryElement?.unit,
                          trend: snapshot.trend,
                          stormIntervals: snapshot.stormIntervals,
                          showHeader: true,
                          fillsVertically: true,
                          headerFont: .footnote,
                          headerStale: snapshot.isStale,
                          windowStart: snapshot.windowStart,
                          windowEnd: snapshot.windowEnd)
        }
    }

    #if os(watchOS)
    private var corner: some View {
        // "F" over "FRD" at the inner corner (broken-link symbol beside "FRD" when stale);
        // the reading curves around the dial.
        VStack(spacing: -2) {
            Text(snapshot.primaryElement?.code ?? "")
                .font(.system(size: 17, weight: .bold))
            cornerStationLabel
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(Color.accentColor)
        .widgetAccentable()
        .minimumScaleFactor(0.5)
        .lineLimit(1)
        .widgetLabel {
            Text(snapshot.primaryValue.map { String(format: "%.2f nT", $0) } ?? "—")
                .foregroundStyle(.primary)
        }
    }

    private var cornerStationLabel: Text {
        guard snapshot.isStale else { return Text(snapshot.observatoryCode) }
        return Text("\(snapshot.observatoryCode) \(Image(systemName: ObsReadingLine.staleSymbol))")
    }
    #endif

    // MARK: - System families (iOS / macOS)

    @ViewBuilder
    private var systemTile: some View {
        switch style {
        case .field:
            fieldTile
        case .chart:
            chartTile
        }
    }

    private var systemHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(snapshot.observatoryCode).font(.headline)
            Spacer()
            Text(snapshot.range.shortLabel).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var fieldTile: some View {
        // Lead with the compact complication-style reading ("FRD F 50083.42 nT →"), tuck the
        // station name close beneath it, and let the chart take all the remaining height.
        VStack(alignment: .leading, spacing: 2) {
            ObsReadingLine(stationCode: snapshot.observatoryCode,
                           element: snapshot.primaryElement?.code,
                           value: snapshot.primaryValue,
                           unit: snapshot.primaryElement?.unit,
                           trend: snapshot.trend,
                           font: .subheadline)
            Text(snapshot.observatoryName)
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.7)
            fieldChart(showHeader: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // Sparkline-dominant tile: the health-style chart carries its own "FRD F 50,083.00 nT →"
    // header (same reading line as the small complication). On the small ("2×2") tile that
    // header stacks onto two lines so it isn't squashed.
    private var chartTile: some View {
        fieldChart(showHeader: true)
    }

    /// The narrow small home-screen tile (absent on watchOS, where `systemSmall` is unavailable).
    private var isSmallSystemFamily: Bool {
        #if os(iOS) || os(macOS)
        return family == .systemSmall
        #else
        return false
        #endif
    }

    @ViewBuilder
    private func fieldChart(showHeader: Bool) -> some View {
        if snapshot.sparkline.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if showHeader { systemHeader }
                sparklineOrPlaceholder(fill: false)
            }
        } else {
            ObsFieldChart(series: snapshot.sparkline,
                          stationCode: snapshot.observatoryCode,
                          element: snapshot.primaryElement?.code,
                          latestValue: snapshot.primaryValue,
                          unit: snapshot.primaryElement?.unit,
                          trend: showHeader ? snapshot.trend : nil,
                          stormIntervals: snapshot.stormIntervals,
                          showHeader: showHeader,
                          headerFont: .subheadline,
                          headerStacked: isSmallSystemFamily,
                          windowStart: snapshot.windowStart,
                          windowEnd: snapshot.windowEnd)
        }
    }

    @ViewBuilder
    private func sparklineOrPlaceholder(fill: Bool) -> some View {
        if !snapshot.sparkline.isEmpty {
            ObsSparkline(series: snapshot.sparkline, lineWidth: 2, showsLatestDot: true, fill: fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Text("No recent data").font(.caption2).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var background: some View {
        switch family {
        case .accessoryInline, .accessoryCircular, .accessoryRectangular:
            Color.clear
        default:
            #if os(watchOS)
            Color.clear
            #else
            LinearGradient(colors: [Color.accentColor.opacity(0.18), Color.accentColor.opacity(0.04)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            #endif
        }
    }

    // MARK: - Formatting

    static func compact(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = abs(value) < 100 ? 1 : 0
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
    }

    static func compactShort(_ value: Double) -> String {
        let magnitude = abs(value)
        if magnitude >= 10_000 { return String(format: "%.1fk", value / 1_000) }
        if magnitude >= 1_000 { return String(format: "%.2fk", value / 1_000) }
        return String(format: "%.0f", value)
    }

    static func signed(_ value: Double) -> String {
        (value >= 0 ? "+" : "") + compact(value)
    }

    /// Field-trajectory arrow. A change of less than 5 nT (over the last 30 minutes) is
    /// shown as a flat/horizontal arrow; otherwise it slopes up or down.
    static let steadyThreshold: Double = 5

    static func trendSymbol(_ value: Double) -> String {
        if value >= steadyThreshold { return "arrow.up.right" }
        if value <= -steadyThreshold { return "arrow.down.right" }
        return "arrow.right"
    }
}
