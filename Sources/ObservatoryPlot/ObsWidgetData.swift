// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0
//
// Shared data loading for the iOS widgets, watch app, and complications. Keeps the
// network bounded (widgets have a tight execution budget) and always falls back to the
// cache so something renders even offline.

import Foundation

/// Latest reading for one element, used by the multi-component widget.
struct GeomagWidgetComponent: Sendable, Identifiable {
    var element: GeomagElement
    var value: Double
    var id: String { element.code }
}

/// A compact snapshot for glanceable surfaces: the primary element's recent trace plus its
/// latest value and short-window trend, every component's current reading, and a simple
/// activity (peak-to-peak) measure for the window.
struct GeomagWidgetSnapshot: Sendable {
    var observatoryCode: String
    var observatoryName: String
    var primaryElement: GeomagElement?
    var primaryValue: Double?
    var primaryTime: Date?
    var trend: Double?            // primary element: latest minus window-start
    var sparkline: [ObsLineSeries]
    var components: [GeomagWidgetComponent]
    var activity: Double?         // primary element: max - min over the window (nT)
    var stormIntervals: [StormInterval]
    var range: ObservatoryTimeRange
    var isPlaceholder: Bool

    var hasData: Bool { primaryValue != nil && !sparkline.isEmpty }
}

enum GeomagWidgetData {
    static func placeholder(code: String = ObservatorySettings.observatoryCode,
                            range: ObservatoryTimeRange = .day) -> GeomagWidgetSnapshot {
        let observatory = Observatories.observatory(code: code) ?? Observatories.default
        let components = [
            GeomagWidgetComponent(element: GeomagElement("X"), value: 21_320),
            GeomagWidgetComponent(element: GeomagElement("Y"), value: -3_980),
            GeomagWidgetComponent(element: GeomagElement("Z"), value: 45_100),
            GeomagWidgetComponent(element: GeomagElement("F"), value: 50_083),
        ]
        return GeomagWidgetSnapshot(
            observatoryCode: observatory.code, observatoryName: observatory.name,
            primaryElement: GeomagElement("F"), primaryValue: 50_083, primaryTime: nil,
            trend: -6, sparkline: [Self.demoSeries(range: range)], components: components, activity: 24,
            stormIntervals: [], range: range, isPlaceholder: true)
    }

    /// Load a snapshot, fetching only the recent window and falling back to cache on
    /// timeout/failure. `network` allows complications to stay strictly on cache.
    static func snapshot(code: String = ObservatorySettings.observatoryCode,
                         range: ObservatoryTimeRange = .day,
                         network: Bool = true,
                         timeout: Double = 18,
                         now: Date = Date()) async -> GeomagWidgetSnapshot {
        let observatory = Observatories.observatory(code: code) ?? Observatories.default
        let window = range.dateRange(now: now)
        let repo = GeomagRepository.shared

        var result: GeomagSeriesResult?
        if network {
            result = await withTimeout(seconds: timeout) {
                try? await repo.series(code: code, from: window.lowerBound, to: window.upperBound,
                                       maxPoints: 80, now: now)
            } ?? nil
        }
        if result == nil || result?.isEmpty == true {
            result = await repo.cachedSeries(code: code, from: window.lowerBound,
                                             to: window.upperBound, maxPoints: 80)
        }

        guard let result, !result.isEmpty else {
            var empty = placeholder(code: code, range: range)
            empty.isPlaceholder = false
            empty.primaryValue = nil
            empty.sparkline = []
            empty.components = []
            empty.activity = nil
            empty.stormIntervals = []
            return empty
        }

        let primaryCode = ObservatoryElementPreference.primary(from: result.series.map { $0.element.code })
        let primarySeries = result.series.first { $0.element.code == primaryCode }
        let trend = primarySeries?.recentChange   // field trajectory over the last 30 minutes
        let activity: Double? = primarySeries.flatMap { s in
            let values = s.samples.map(\.value)
            guard let lo = values.min(), let hi = values.max() else { return nil }
            return hi - lo
        }
        let spark = primarySeries.map { [$0.obsLineSeries(index: 0)] } ?? []
        let components = result.series.compactMap { s in
            s.latest.map { GeomagWidgetComponent(element: s.element, value: $0.value) }
        }

        return GeomagWidgetSnapshot(
            observatoryCode: observatory.code, observatoryName: observatory.name,
            primaryElement: primarySeries?.element,
            primaryValue: primarySeries?.latest?.value,
            primaryTime: primarySeries?.latest.map { Date(timeIntervalSince1970: $0.time) },
            trend: trend, sparkline: spark, components: components, activity: activity,
            stormIntervals: primarySeries?.stormIntervals ?? [],
            range: range, isPlaceholder: false)
    }

    private static func demoSeries(range: ObservatoryTimeRange, now: Date = Date()) -> ObsLineSeries {
        let end = now.timeIntervalSince1970
        let start = end - range.duration
        let count = 80
        let base = 50_083.0
        let points = (0..<count).map { i -> ObsPlotPoint in
            let frac = Double(i) / Double(count - 1)
            let t = start + frac * (end - start)
            let phase = frac * 2 * Double.pi
            let v = base + 8 * sin(phase) + 4 * sin(phase * 3)
            return ObsPlotPoint(x: t, y: v)
        }
        return ObsLineSeries(index: 0, label: "F", unit: "nT", points: points)
    }
}

/// Run async `work`, returning its result, or nil if it doesn't finish within `seconds`.
func withTimeout<T: Sendable>(seconds: Double, _ work: @escaping @Sendable () async -> T?) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await work() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}
