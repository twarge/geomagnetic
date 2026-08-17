// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0
//
// Sharing for the detail screen: the visible chart as a PNG and the window's minute data
// as CSV. Modeled on Profiler's MeasurementExport: constructing the export is a value
// copy, and the PNG render / cache read happen only when a share target actually asks.
//
// This file belongs to the Observatory app target only (iOS + macOS), keeping the
// ShareLink/ImageRenderer machinery out of the watch builds.

import CoreGraphics
import CoreTransferable
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// The detail view, captured whole at share time: station identity, the plotted traces,
/// and the visible window — so the exported chart and CSV describe the same view even if
/// the screen refreshes while the share sheet is up.
struct GeomagExport {
    var observatory: GeomagObservatory
    var stationName: String?     // from the IAGA-2002 header, when available
    var source: String?          // operating institute, for attribution
    var rangeLabel: String       // e.g. "1 Day"
    var series: [ObsLineSeries]  // the traces on screen (display-decimated)
    var xRange: ObsPlotRange     // the visible window, epoch seconds UTC
    var yRange: ObsPlotRange?    // the user's vertical zoom; nil ⇒ autoscale
    var yAxisLabel: String

    /// Shared base name — "geomag-FRD-2026-08-17", dated by the UTC day the window ends
    /// on — so one export's files sort together wherever they land.
    var stem: String {
        "geomag-\(observatory.code)-\(UTCDate.dayString(UTCDate.startOfDay(xRange.maximum)))"
    }

    func file(_ content: GeomagExportFile.Content) -> GeomagExportFile {
        GeomagExportFile(content: content, export: self)
    }

    /// Both artifacts, as offered by the "Chart & Data" entry.
    var shareFiles: [GeomagExportFile] {
        [file(.chart), file(.data)]
    }

    // MARK: - Chart text

    var title: String { "\(stationName ?? observatory.name) (\(observatory.code))" }

    var subtitle: String {
        let start = Date(timeIntervalSince1970: xRange.minimum)
        let end = Date(timeIntervalSince1970: xRange.maximum)
        let elements = series.map(\.label).joined(separator: ", ")
        return "\(elements) · \(rangeLabel) · "
            + "\(start.formatted(date: .abbreviated, time: .shortened)) – "
            + end.formatted(date: .abbreviated, time: .shortened)
    }

    /// The credit INTERMAGNET's conditions of use ask for (non-commercial, attribution),
    /// baked into the rendered pixels so it survives wherever the PNG lands.
    var attribution: String {
        var credit = "Data collected at \(stationName ?? observatory.name) (\(observatory.code))"
        if let source, !source.isEmpty { credit += " by \(source)" }
        return credit + " · INTERMAGNET · intermagnet.org · CC BY-NC 4.0"
    }

    /// Vertical extent for the share render: the user's zoom when set, else the traces'
    /// own extent within the visible window (matching the on-screen autoscale).
    var resolvedYRange: ObsPlotRange {
        if let yRange { return yRange }
        let visible = series.flatMap { item in
            item.points.filter { $0.x >= xRange.minimum && $0.x <= xRange.maximum }.map(\.y)
        }
        if let range = ObsPlotRange(optionalValues: visible) { return range }
        return ObsPlotRange(values: series.flatMap { $0.points.map(\.y) })
    }

    // MARK: - Encoders

    /// PNG via ImageIO rather than the AppKit or UIKit image classes, which exist on only
    /// one platform each. Rendered at 2× from the dedicated, non-interactive share view.
    @MainActor
    func pngData() throws -> Data {
        let renderer = ImageRenderer(content: GeomagShareChartView(export: self))
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let data = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(
                  data, UTType.png.identifier as CFString, 1, nil)
        else {
            throw NSError(
                domain: "Observatory", code: 10,
                userInfo: [NSLocalizedDescriptionKey: "Could not render the chart image."])
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(
                domain: "Observatory", code: 11,
                userInfo: [NSLocalizedDescriptionKey: "Could not encode the chart image as PNG."])
        }
        return data as Data
    }

    /// Full-resolution minute data for the exported window, read back from the per-day
    /// cache — the same files the displayed series were assembled from — so the CSV
    /// carries every sample, not the plot's decimated envelope. Times are ISO8601 UTC;
    /// columns are the elements the station reported, in cache column order; a missing
    /// or flagged sample is an empty field.
    func csvData() -> Data {
        let store = GeomagStore()
        let from = Date(timeIntervalSince1970: xRange.minimum)
        let to = Date(timeIntervalSince1970: xRange.maximum)
        let days = UTCDate.dayStarts(from: from, to: to)
            .compactMap { store.loadDay(code: observatory.code, dayStart: $0) }
            .filter { !$0.isEmpty }
            .sorted { $0.dayStart < $1.dayStart }

        // Canonical element order: the union across days, first-seen first (mirrors
        // GeomagRepository.buildSeries, so the CSV matches what the app plots from).
        var elements: [String] = []
        for day in days {
            for element in day.elements where !elements.contains(element) {
                elements.append(element)
            }
        }

        var text = "time_utc"
        for element in elements {
            text += ",\(element)_\(GeomagElement(element).unit)"
        }
        text += "\n"

        for day in days {
            let columns = elements.map { day.columnIndex(of: $0) }
            for index in 0..<day.sampleCount {
                let time = day.time(at: index)
                guard time >= xRange.minimum, time <= xRange.maximum else { continue }
                var row = ""
                var hasValue = false
                for column in columns {
                    row += ","
                    guard let column else { continue }
                    let value = day.values[column][index]
                    guard value.isFinite else { continue }
                    row += String(format: "%.2f", value)
                    hasValue = true
                }
                guard hasValue else { continue }   // all-gap rows are noise
                text += Self.timeFormatter.string(from: Date(timeIntervalSince1970: time)) + row + "\n"
            }
        }
        return Data(text.utf8)
    }

    private static let timeFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

/// One artifact of an export, typed for transfer through the share sheet. A single type
/// rather than one per artifact because `ShareLink`'s "Chart & Data" entry wants a
/// homogeneous collection; the exporting conditions steer each instance to the one
/// representation that matches its content (the Profiler pattern).
struct GeomagExportFile: Transferable {
    enum Content: Equatable {
        case chart, data
    }

    var content: Content
    var export: GeomagExport

    var filename: String {
        switch content {
        case .chart: return export.stem + ".png"
        case .data: return export.stem + ".csv"
        }
    }

    var iconSystemName: String {
        switch content {
        case .chart: return "photo"
        case .data: return "tablecells"
        }
    }

    /// The type this artifact transfers as, and the key the representations below are
    /// selected by — so a content case cannot end up offering one extension under a
    /// different transfer type.
    var contentType: UTType {
        switch content {
        case .chart: return .png
        case .data: return .commaSeparatedText
        }
    }

    func data() async throws -> Data {
        switch content {
        case .chart: return try await export.pngData()
        case .data: return export.csvData()
        }
    }

    /// One representation per exported type, each offered only for the content that
    /// carries it. Built through the helper below with every closure's types spelled
    /// out, which keeps the result builder cheap for the type checker (see Profiler's
    /// ExportFile for the cautionary tale).
    static var transferRepresentation: some TransferRepresentation {
        fileRepresentation(.png)
        fileRepresentation(.commaSeparatedText)
    }

    private static func fileRepresentation(
        _ type: UTType
    ) -> some TransferRepresentation<GeomagExportFile> {
        let representation = FileRepresentation<GeomagExportFile>(exportedContentType: type) {
            (file: GeomagExportFile) async throws -> SentTransferredFile in
            SentTransferredFile(try await file.writeTemporary(), allowAccessingOriginalFile: false)
        }
        return representation.exportingCondition { (file: GeomagExportFile) -> Bool in
            file.contentType == type
        }
    }

    /// File transfers hand over a URL, so the bytes go through a uniquely-named temporary
    /// directory — which is also what lets the receiver see the real filename.
    private func writeTemporary() async throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(filename)
        try await data().write(to: url)
        return url
    }
}

/// The share rendition of the detail chart: title, the visible window's traces, and the
/// INTERMAGNET attribution footer. Fixed-size, non-interactive, and always light, so the
/// exported PNG is deterministic wherever it's rendered. The drawing mirrors
/// ObsLinePlotView's axes and traces through the shared plot primitives.
struct GeomagShareChartView: View {
    let export: GeomagExport

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(export.title)
                        .font(.title3.weight(.semibold))
                    Text(export.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if export.series.count > 1 { legend }
            }
            chart
                .frame(height: 350)
            Text(export.attribution)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 760)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach(export.series) { item in
                HStack(spacing: 5) {
                    Circle()
                        .fill(ObsPlotSeriesPalette.color(at: item.index))
                        .frame(width: 7, height: 7)
                    Text(item.label)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var chart: some View {
        Canvas { context, size in
            let plotRect = ObsPlotLayout.plotRect(for: size)
            let xRange = export.xRange
            let yRange = export.resolvedYRange
            let drawable = export.series.filter { $0.points.count >= 2 }

            func point(for plotPoint: ObsPlotPoint) -> CGPoint {
                CGPoint(x: plotRect.minX + plotRect.width * CGFloat(xRange.unclampedRatio(for: plotPoint.x)),
                        y: plotRect.maxY - plotRect.height * CGFloat(yRange.unclampedRatio(for: plotPoint.y)))
            }

            // No-data hatch over gaps in the record, matching the app's chart.
            let xs = drawable.flatMap { $0.points.map(\.x) }.sorted()
            for gap in ObsPlotHatch.missingIntervals(sampleTimes: xs,
                                                     domain: xRange.minimum...xRange.maximum) {
                let x0 = plotRect.minX + plotRect.width * CGFloat(xRange.unclampedRatio(for: gap.lowerBound))
                let x1 = plotRect.minX + plotRect.width * CGFloat(xRange.unclampedRatio(for: gap.upperBound))
                let clamped0 = min(max(x0, plotRect.minX), plotRect.maxX)
                let clamped1 = min(max(x1, plotRect.minX), plotRect.maxX)
                if clamped1 - clamped0 > 0.5 {
                    ObsPlotHatch.draw(context, in: CGRect(x: clamped0, y: plotRect.minY,
                                                          width: clamped1 - clamped0,
                                                          height: plotRect.height))
                }
            }

            // Grid, tick labels, and frame — the interactive plot's axis construction.
            var gridPath = Path()
            let xDescriptor = ObsAxisDescriptor.makeX(kind: .time(timeZone: .current),
                                                      range: xRange, tickCount: 5)
            let yTicks = yRange.ticks(count: 5)
            let yDecimals = Self.decimals(forTicks: yTicks)
            for value in yTicks {
                let y = plotRect.maxY - plotRect.height * CGFloat(yRange.ratio(for: value))
                gridPath.move(to: CGPoint(x: plotRect.minX, y: y))
                gridPath.addLine(to: CGPoint(x: plotRect.maxX, y: y))
                context.draw(
                    Text(String(format: "%.\(yDecimals)f", value)).font(.caption).foregroundStyle(.secondary),
                    at: CGPoint(x: plotRect.minX - 6, y: y), anchor: .trailing)
            }
            for value in xDescriptor.ticks {
                let x = plotRect.minX + plotRect.width * CGFloat(xRange.ratio(for: value))
                gridPath.move(to: CGPoint(x: x, y: plotRect.minY))
                gridPath.addLine(to: CGPoint(x: x, y: plotRect.maxY))
                context.draw(
                    Text(xDescriptor.label(for: value)).font(.caption).foregroundStyle(.secondary),
                    at: CGPoint(x: x, y: plotRect.maxY + 6), anchor: .top)
            }
            context.stroke(gridPath, with: .color(.secondary.opacity(0.18)), lineWidth: 1)

            var axisPath = Path()
            axisPath.move(to: CGPoint(x: plotRect.minX, y: plotRect.minY))
            axisPath.addLine(to: CGPoint(x: plotRect.minX, y: plotRect.maxY))
            axisPath.addLine(to: CGPoint(x: plotRect.maxX, y: plotRect.maxY))
            context.stroke(axisPath, with: .color(.secondary.opacity(0.45)), lineWidth: 1)

            ObsPlotAxisLabelDrawer.drawYAxisLabel(export.yAxisLabel, context: context, plotRect: plotRect)
            context.draw(
                Text("Time").font(.caption.weight(.semibold)).foregroundStyle(.secondary),
                at: CGPoint(x: plotRect.midX, y: size.height - 3), anchor: .bottom)
            if let offsetLabel = xDescriptor.offsetLabel {
                context.draw(
                    Text(offsetLabel).font(.caption2).foregroundStyle(.secondary),
                    at: CGPoint(x: plotRect.minX, y: size.height - 3), anchor: .bottomLeading)
            }

            // Traces, clipped to the plot area.
            var clippedContext = context
            clippedContext.clip(to: Path(plotRect))
            for item in drawable {
                let color = ObsPlotSeriesPalette.color(at: item.index)
                var linePath = Path()
                linePath.move(to: point(for: item.points[0]))
                for plotPoint in item.points.dropFirst() {
                    linePath.addLine(to: point(for: plotPoint))
                }
                clippedContext.stroke(linePath, with: .color(color), lineWidth: 1.6)
            }
        }
    }

    private static func decimals(forTicks ticks: [Double]) -> Int {
        guard ticks.count >= 2 else { return 1 }
        let step = abs(ticks[1] - ticks[0])
        guard step.isFinite, step > 0 else { return 1 }
        return min(4, max(0, Int(ceil(-log10(step)))))
    }
}
