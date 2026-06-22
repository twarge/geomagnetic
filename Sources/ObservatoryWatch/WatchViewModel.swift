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
