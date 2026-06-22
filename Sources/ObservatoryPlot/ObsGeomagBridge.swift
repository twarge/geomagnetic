// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0
//
// Adapts the data layer's `GeomagSeries` into the plot's `ObsLineSeries`, so the app,
// widgets, watch app, and complications share one conversion.

import Foundation

extension GeomagSeries {
    /// Convert to a plot series. `index` selects the palette color and should be stable
    /// across refreshes (use the element's position in the available list).
    func obsLineSeries(index: Int) -> ObsLineSeries {
        ObsLineSeries(
            index: index,
            label: element.shortName,
            unit: element.unit,
            points: samples.map { ObsPlotPoint(x: $0.time, y: $0.value) }
        )
    }
}

extension Array where Element == GeomagSeries {
    func obsLineSeries() -> [ObsLineSeries] {
        enumerated().map { $0.element.obsLineSeries(index: $0.offset) }
    }
}

extension GeomagSeriesResult {
    func obsLineSeries() -> [ObsLineSeries] { series.obsLineSeries() }

    /// Full horizontal extent for the plot: prefer the covered span, fall back to the
    /// requested window so an empty/partial result still frames the right time axis.
    var fullXRange: ObsPlotRange? {
        if let covered = coveredRange, covered.upperBound > covered.lowerBound {
            return ObsPlotRange(minimum: covered.lowerBound, maximum: covered.upperBound)
        }
        return ObsPlotRange(minimum: requestedRange.lowerBound, maximum: requestedRange.upperBound)
    }

    /// The most recent finite sample across all series (for "current value" displays).
    var latestSample: (element: GeomagElement, sample: GeomagSample)? {
        var best: (GeomagElement, GeomagSample)?
        for s in series {
            guard let last = s.latest else { continue }
            if best == nil || last.time > best!.1.time {
                best = (s.element, last)
            }
        }
        return best
    }
}
