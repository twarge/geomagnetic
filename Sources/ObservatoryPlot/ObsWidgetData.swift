// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0
//
// Shared data loading for the iOS widgets, watch app, and complications. Keeps the
// network bounded (widgets have a tight execution budget) and always falls back to the
// cache so something renders even offline.

import Foundation

/// Latest reading (and trailing trend) for one element, used by the multi-component widget.
struct GeomagWidgetComponent: Sendable, Identifiable {
    var element: GeomagElement
    var value: Double
    var trend: Double?     // net change over the trailing trend window
    var id: String { element.code }

    /// Trend as a rate per hour (the trend window is currently 30 minutes).
    var trendPerHour: Double? {
        trend.map { $0 * 3_600 / GeomagRepository.trendWindowSeconds }
    }
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
    /// Intended window in epoch seconds ([now − range, now]); lets the chart place cached data
    /// at its true time and hatch the stretch that's missing when offline. nil ⇒ fit to data.
    var windowStart: Double? = nil
    var windowEnd: Double? = nil
    /// Why the newest available measurement is old (when it is): the mirror couldn't be
    /// reached at all, or the mirror answered but the observatory source is behind.
    /// Complications flag the two cases with distinct symbols.
    var staleCause: GeomagStaleCause = .fresh

    var isStale: Bool { staleCause != .fresh }

    /// Badge for the stale state, nil when fresh: a broken link when the mirror is
    /// unreachable, a late clock when the mirror is fine but the source is behind.
    var staleSymbol: String? {
        switch staleCause {
        case .fresh: return nil
        case .unreachable: return "personalhotspot.slash"
        case .sourceStale: return "clock.badge.exclamationmark"
        }
    }

    var hasData: Bool { primaryValue != nil && !sparkline.isEmpty }

    /// The trend expressed as a rate: nT per hour (trend covers the repository's trailing
    /// trend window, currently 30 minutes, so this rescales it to a full hour).
    var trendPerHour: Double? {
        trend.map { $0 * 3_600 / GeomagRepository.trendWindowSeconds }
    }

    /// Min…max of the primary element over the window (for the corner range gauge).
    var primaryRange: ClosedRange<Double>? {
        let values = sparkline.first?.points.map(\.y) ?? []
        guard let lo = values.min(), let hi = values.max(), hi > lo else { return nil }
        return lo...hi
    }
}

/// Why glanceable data is stale (when it is).
enum GeomagStaleCause: Sendable {
    case fresh
    case unreachable   // couldn't reach the mirror at all
    case sourceStale   // mirror answered, but the observatory source is behind
}

enum GeomagWidgetData {
    /// Newest measurement older than this ⇒ the snapshot is marked stale. Matches the
    /// chart's no-data hatch floor, so ordinary publication latency never trips it.
    static let staleAfterSeconds: Double = 40 * 60

    static func placeholder(code: String = ObservatorySettings.observatoryCode,
                            range: ObservatoryTimeRange = .day) -> GeomagWidgetSnapshot {
        let observatory = Observatories.observatory(code: code) ?? Observatories.default
        let components = [
            GeomagWidgetComponent(element: GeomagElement("F"), value: 50_083, trend: -15),
            GeomagWidgetComponent(element: GeomagElement("X"), value: 21_320, trend: 2),
            GeomagWidgetComponent(element: GeomagElement("Y"), value: -3_980, trend: -1),
            GeomagWidgetComponent(element: GeomagElement("Z"), value: 45_100, trend: 6),
        ]
        let window = range.dateRange()
        return GeomagWidgetSnapshot(
            observatoryCode: observatory.code, observatoryName: observatory.name,
            primaryElement: GeomagElement("F"), primaryValue: 50_083, primaryTime: nil,
            trend: -6, sparkline: [Self.demoSeries(range: range)], components: components, activity: 24,
            stormIntervals: [], range: range, isPlaceholder: true,
            windowStart: window.lowerBound.timeIntervalSince1970,
            windowEnd: window.upperBound.timeIntervalSince1970)
    }

    /// Load a snapshot, fetching only the recent window and falling back to cache on
    /// timeout/failure. `network` allows complications to stay strictly on cache.
    static func snapshot(code: String = ObservatorySettings.observatoryCode,
                         range: ObservatoryTimeRange = .day,
                         network: Bool = true,
                         timeout: Double = 18,
                         maxPoints: Int = 80,
                         preferredElement: String? = nil,
                         now: Date = Date()) async -> GeomagWidgetSnapshot {
        let observatory = Observatories.observatory(code: code) ?? Observatories.default
        let window = range.dateRange(now: now)
        let repo = GeomagRepository.shared

        var result: GeomagSeriesResult?
        var networkFailed = false
        if network {
            result = await withTimeout(seconds: timeout) {
                // Compact path: the mirror returns ~80 server-decimated points + storm bands
                // as a few KB, instead of whole UTC days of IAGA text — a large saving over
                // the watch radio especially. Falls back to the whole-day repository fetch
                // when /v1 is unavailable (e.g. OBSERVATORY_BASE_URL points at the raw GIN).
                if let compact = try? await MirrorClient.shared.series(
                    code: code, from: window.lowerBound, to: window.upperBound,
                    maxPoints: maxPoints, storms: true) {
                    return compact
                }
                return try? await repo.series(code: code, from: window.lowerBound, to: window.upperBound,
                                              maxPoints: maxPoints, now: now)
            } ?? nil
            // Both network paths failing (or timing out) means the mirror is unreachable;
            // a response with old data means the mirror is fine but the source is behind.
            networkFailed = (result == nil)
        }
        if result == nil || result?.isEmpty == true {
            result = await repo.cachedSeries(code: code, from: window.lowerBound,
                                             to: window.upperBound, maxPoints: maxPoints)
        }

        guard let result, !result.isEmpty else {
            var empty = placeholder(code: code, range: range)
            empty.isPlaceholder = false
            empty.primaryValue = nil
            empty.sparkline = []
            empty.components = []
            empty.activity = nil
            empty.stormIntervals = []
            empty.windowStart = window.lowerBound.timeIntervalSince1970
            empty.windowEnd = window.upperBound.timeIntervalSince1970
            empty.staleCause = networkFailed ? .unreachable : .sourceStale
            return empty
        }

        let reported = result.series.map { $0.element.code }
        // A widget configured to a specific component wins; otherwise the F-first preference.
        let primaryCode = preferredElement.flatMap { reported.contains($0) ? $0 : nil }
            ?? ObservatoryElementPreference.primary(from: reported)
        let primarySeries = result.series.first { $0.element.code == primaryCode }
        let trend = primarySeries?.recentChange   // field trajectory over the last 30 minutes
        let activity: Double? = primarySeries.flatMap { s in
            let values = s.samples.map(\.value)
            guard let lo = values.min(), let hi = values.max() else { return nil }
            return hi - lo
        }
        let spark = primarySeries.map { [$0.obsLineSeries(index: 0)] } ?? []
        // F first, then the rest in reported order — matching the app's headline ordering.
        let ordered = result.series.sorted {
            ($0.element.code == primaryCode ? 0 : 1) < ($1.element.code == primaryCode ? 0 : 1)
        }
        let components = ordered.compactMap { s in
            s.latest.map { GeomagWidgetComponent(element: s.element, value: $0.value, trend: s.recentChange) }
        }

        let latestTime = primarySeries?.latest?.time
        let dataOld = latestTime.map { now.timeIntervalSince1970 - $0 > staleAfterSeconds } ?? true
        let staleCause: GeomagStaleCause = dataOld ? (networkFailed ? .unreachable : .sourceStale) : .fresh
        return GeomagWidgetSnapshot(
            observatoryCode: observatory.code, observatoryName: observatory.name,
            primaryElement: primarySeries?.element,
            primaryValue: primarySeries?.latest?.value,
            primaryTime: primarySeries?.latest.map { Date(timeIntervalSince1970: $0.time) },
            trend: trend, sparkline: spark, components: components, activity: activity,
            stormIntervals: primarySeries?.stormIntervals ?? [],
            range: range, isPlaceholder: false,
            windowStart: window.lowerBound.timeIntervalSince1970,
            windowEnd: window.upperBound.timeIntervalSince1970,
            staleCause: staleCause)
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
