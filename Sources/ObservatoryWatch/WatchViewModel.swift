// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

@MainActor
final class WatchViewModel: ObservableObject {
    @Published var code: String
    @Published var range: ObservatoryTimeRange
    @Published private(set) var result: GeomagSeriesResult?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    init() {
        code = ObservatorySettings.observatoryCode
        range = ObservatorySettings.timeRange
    }

    var observatory: GeomagObservatory { Observatories.observatory(code: code) ?? Observatories.default }

    /// Full station name from the data's IAGA header when available, else the bundled name.
    var stationName: String {
        if let name = result?.stationName, !name.isEmpty { return name }
        return observatory.name
    }

    /// Complete "Source of Data" text from the IAGA header (no abbreviation), shown as the
    /// attribution below the graphs.
    var sourceText: String? {
        guard let source = result?.source, !source.isEmpty else { return nil }
        return source
    }

    /// One graph per reported element, F first, then X / Y / Z, then the rest.
    var elementGraphs: [WatchElementGraph] {
        guard let result else { return [] }
        let order = ["F", "X", "Y", "Z", "H", "D", "G", "I", "S"]
        return result.series.sorted {
            (order.firstIndex(of: $0.element.code) ?? 99) < (order.firstIndex(of: $1.element.code) ?? 99)
        }.map {
            WatchElementGraph(element: $0.element, value: $0.latest?.value, trend: $0.recentChange,
                              sparkline: [$0.obsLineSeries(index: 0)], storms: $0.stormIntervals)
        }
    }

    func load(force: Bool = false) async {
        isLoading = true
        errorMessage = nil
        let window = range.dateRange()
        do {
            result = try await GeomagRepository.shared.series(
                code: code, from: window.lowerBound, to: window.upperBound,
                maxPoints: 360, forceRefresh: force)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    func select(_ newCode: String) {
        guard newCode != code else { return }
        code = newCode
        ObservatorySettings.observatoryCode = newCode
        result = nil
    }

    func setRange(_ newRange: ObservatoryTimeRange) {
        guard newRange != range else { return }
        range = newRange
        ObservatorySettings.timeRange = newRange
    }

    var primary: (element: GeomagElement, sample: GeomagSample)? {
        guard let result else { return nil }
        let chosen = ObservatoryElementPreference.primary(from: result.series.map { $0.element.code })
        guard let chosen,
              let series = result.series.first(where: { $0.element.code == chosen }),
              let sample = series.latest else { return nil }
        return (series.element, sample)
    }

    /// Field trajectory over the last 30 minutes (latest minus ~30 min earlier).
    var trend: Double? {
        guard let primaryCode = primary?.element.code else { return nil }
        return result?.series.first(where: { $0.element.code == primaryCode })?.recentChange
    }

    var primarySparkline: [ObsLineSeries] {
        guard let primaryCode = primary?.element.code,
              let series = result?.series.first(where: { $0.element.code == primaryCode }) else { return [] }
        return [series.obsLineSeries(index: 0)]
    }

    var stormIntervals: [StormInterval] {
        guard let primaryCode = primary?.element.code else { return [] }
        return result?.series.first(where: { $0.element.code == primaryCode })?.stormIntervals ?? []
    }

    /// Field components (nT) for the full plot view.
    var plotSeries: [ObsLineSeries] {
        guard let result else { return [] }
        return result.series.enumerated().compactMap { index, series in
            series.element.unit == "nT" ? series.obsLineSeries(index: index) : nil
        }
    }

    var fullXRange: ObsPlotRange? {
        if let covered = result?.coveredRange, covered.upperBound > covered.lowerBound {
            return ObsPlotRange(minimum: covered.lowerBound, maximum: covered.upperBound)
        }
        let window = range.dateRange()
        return ObsPlotRange(minimum: window.lowerBound.timeIntervalSince1970,
                            maximum: window.upperBound.timeIntervalSince1970)
    }

    var hasData: Bool { !(result?.isEmpty ?? true) }
}

/// One element's compact graph for the watch's scrollable stack.
struct WatchElementGraph: Identifiable {
    let element: GeomagElement
    let value: Double?
    let trend: Double?
    let sparkline: [ObsLineSeries]
    let storms: [StormInterval]
    var id: String { element.code }
}
