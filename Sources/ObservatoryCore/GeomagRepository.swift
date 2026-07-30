// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Resolves a view (observatory + time window + elements) into plottable series while
/// touching the network as little as possible.
///
/// Policy:
/// - The unit of work is a UTC day. A view needs exactly the days its window spans.
/// - A finalized cached day (any day strictly before today) is immutable, so it is never
///   re-fetched — this is "only fetch data that is new".
/// - Today (and any not-yet-finalized recent day) is re-fetched only after a short
///   staleness interval, so panning/zooming within the loaded window costs nothing.
/// - Needed days are coalesced into contiguous runs and fetched with a single GIN request
///   each (`dataDuration`), then split back into per-day cache files.
public actor GeomagRepository {
    public static let shared = GeomagRepository()

    private let client: GINClient
    private let store: GeomagStore
    private let cadence: GINClient.Cadence

    /// How long a non-final cached day is trusted before re-fetching.
    public var minRefreshInterval: TimeInterval = 300

    /// The mirror's most recently reported upstream (GIN) health, kept so series results
    /// can carry it even when a load was served without a fresh network roundtrip.
    private var lastUpstream: GeomagUpstreamStatus?

    public init(client: GINClient = GINClient(),
                store: GeomagStore = GeomagStore(),
                cadence: GINClient.Cadence = .minute) {
        self.client = client
        self.store = store
        self.cadence = cadence
    }

    /// "Now", overridable for testing. Production passes the real clock from `series`.
    private func currentDate(_ now: Date?) -> Date { now ?? Date() }

    // MARK: - Public API

    /// Resolve the days covering `[from, to]`, fetching only what's missing or stale.
    /// `forceRefresh` additionally re-fetches the not-yet-final days (e.g. today) even if
    /// they're within the staleness window — used by an explicit pull-to-refresh.
    public func days(code: String, from: Date, to: Date,
                     forceRefresh: Bool = false, now: Date? = nil) async throws -> [GeomagDay] {
        let now = currentDate(now)
        let today = UTCDate.startOfDay(now)
        let wanted = UTCDate.dayStarts(from: from, to: to)

        // 1. Decide which days still need a network fetch.
        var cached: [Double: GeomagDay] = [:]
        var needed: [Double] = []
        for dayStart in wanted {
            let day = store.loadDay(code: code, dayStart: dayStart)
            if let day { cached[dayStart] = day }
            if shouldFetch(day, dayStart: dayStart, today: today, now: now, forceRefresh: forceRefresh) {
                needed.append(dayStart)
            }
        }

        // 2. Fetch needed days as contiguous runs, one request per run.
        for run in contiguousRuns(needed) {
            let durationDays = Int(((run.last! - run.first!) / UTCDate.secondsPerDay).rounded()) + 1
            do {
                let (fetched, upstream) = try await client.fetchDays(
                    code: code, startDayEpoch: run.first!, durationDays: durationDays,
                    cadence: cadence, today: today, now: now)
                if let upstream { lastUpstream = upstream }
                var produced = Set<Double>()
                for day in fetched {
                    store.saveDay(day)
                    cached[day.dayStart] = day
                    produced.insert(day.dayStart)
                }
                // Days in the run that returned nothing: cache a placeholder so we don't
                // hammer the service, finalizing only once they're old enough to be a
                // permanent gap.
                for dayStart in run where !produced.contains(dayStart) {
                    let placeholder = emptyDay(code: code, dayStart: dayStart, today: today, now: now)
                    store.saveDay(placeholder)
                    cached[dayStart] = placeholder
                }
            } catch GeomagError.noData {
                for dayStart in run {
                    let placeholder = emptyDay(code: code, dayStart: dayStart, today: today, now: now)
                    store.saveDay(placeholder)
                    cached[dayStart] = placeholder
                }
            }
            // Other errors (network, service) propagate so the UI can show them, but any
            // days fetched/saved by earlier runs are retained.
        }

        // New days were stored — re-apply the retention caps for this station.
        if !needed.isEmpty {
            store.prune(code: code, now: now)
        }

        return wanted.compactMap { cached[$0] }.filter { !$0.isEmpty }.sorted { $0.dayStart < $1.dayStart }
    }

    /// Resolve `[from, to]` into decimated, plottable series — one per requested element.
    public func series(code: String, from: Date, to: Date,
                       elements requested: [String]? = nil,
                       maxPoints: Int = 1_024, forceRefresh: Bool = false,
                       now: Date? = nil) async throws -> GeomagSeriesResult {
        let fromEpoch = from.timeIntervalSince1970
        let toEpoch = to.timeIntervalSince1970
        let requestedRange = min(fromEpoch, toEpoch)...max(fromEpoch, toEpoch)

        let days = try await days(code: code, from: from, to: to, forceRefresh: forceRefresh, now: now)
        var result = Self.buildSeries(days: days, requestedRange: requestedRange,
                                      requestedElements: requested, maxPoints: maxPoints,
                                      code: code)
        result.upstream = lastUpstream
        return result
    }

    /// Cache-only series assembly (no network) — the fast path for widgets/complications
    /// that must render within a tight time budget.
    public func cachedSeries(code: String, from: Date, to: Date,
                             elements requested: [String]? = nil,
                             maxPoints: Int = 256) -> GeomagSeriesResult {
        let fromEpoch = from.timeIntervalSince1970
        let toEpoch = to.timeIntervalSince1970
        let requestedRange = min(fromEpoch, toEpoch)...max(fromEpoch, toEpoch)
        let days = UTCDate.dayStarts(from: from, to: to)
            .compactMap { store.loadDay(code: code, dayStart: $0) }
            .filter { !$0.isEmpty }
        return Self.buildSeries(days: days, requestedRange: requestedRange,
                                requestedElements: requested, maxPoints: maxPoints, code: code)
    }

    /// Cheap, cache-only latest reading for widgets/complications. Does not hit the network.
    public func cachedLatest(code: String, element: String) -> GeomagSample? {
        guard let day = store.mostRecentDay(code: code),
              let column = day.columnIndex(of: element) else { return nil }
        let values = day.values[column]
        for index in stride(from: values.count - 1, through: 0, by: -1) where values[index].isFinite {
            return GeomagSample(time: day.time(at: index), value: Double(values[index]))
        }
        return nil
    }

    /// Elements available in the most recent cached day.
    public func cachedElements(code: String) -> [String] {
        store.mostRecentDay(code: code)?.elements ?? []
    }

    public func cacheSizeBytes() -> Int64 { store.cacheSizeBytes() }
    public func clearCache() { store.clear() }

    // MARK: - Fetch decision

    private func shouldFetch(_ cached: GeomagDay?, dayStart: Double, today: Double,
                             now: Date, forceRefresh: Bool) -> Bool {
        guard let cached else { return true }
        if cached.isFinal { return false }
        if forceRefresh { return true }
        return now.timeIntervalSince(cached.fetchedAt) >= minRefreshInterval
    }

    private func emptyDay(code: String, dayStart: Double, today: Double, now: Date) -> GeomagDay {
        let age = now.timeIntervalSince1970 - dayStart
        let isFinal = dayStart < today && age > GINClient.finalizeIncompleteAfter
        return GeomagDay(observatoryCode: code.uppercased(), dayStart: dayStart,
                         cadence: cadence.seconds, elements: [], values: [],
                         isFinal: isFinal, fetchedAt: now)
    }

    private func contiguousRuns(_ dayStarts: [Double]) -> [[Double]] {
        guard !dayStarts.isEmpty else { return [] }
        let sorted = dayStarts.sorted()
        var runs: [[Double]] = []
        var current: [Double] = [sorted[0]]
        for dayStart in sorted.dropFirst() {
            if dayStart - current.last! <= UTCDate.secondsPerDay + 1 {
                current.append(dayStart)
            } else {
                runs.append(current)
                current = [dayStart]
            }
        }
        runs.append(current)
        return runs
    }

    // MARK: - Series assembly (pure, testable)

    static func buildSeries(days: [GeomagDay], requestedRange: ClosedRange<Double>,
                            requestedElements: [String]?, maxPoints: Int,
                            code: String) -> GeomagSeriesResult {
        // Canonical element order: the union across days, first-seen first. (Taking only the
        // first day's list used to hide elements when cached days had mixed orientations.)
        var available: [String] = []
        for day in days {
            for element in day.elements where !available.contains(element) {
                available.append(element)
            }
        }
        let elements: [String]
        if let requestedElements {
            let wanted = requestedElements.map { $0.uppercased() }
            elements = available.filter { wanted.contains($0) }
        } else {
            elements = available
        }

        var seriesList: [GeomagSeries] = []
        var coveredLo = Double.greatestFiniteMagnitude
        var coveredHi = -Double.greatestFiniteMagnitude

        for element in elements {
            var samples: [GeomagSample] = []
            for day in days {
                guard let column = day.columnIndex(of: element) else { continue }
                let values = day.values[column]
                for index in 0..<values.count {
                    let value = values[index]
                    guard value.isFinite else { continue }
                    let time = day.time(at: index)
                    guard requestedRange.contains(time) else { continue }
                    samples.append(GeomagSample(time: time, value: Double(value)))
                    coveredLo = min(coveredLo, time)
                    coveredHi = max(coveredHi, time)
                }
            }
            samples.sort { $0.time < $1.time }
            let storms = StormDetector.intervals(from: samples)   // from full-res, before decimation
            let recentChange = netChange(samples, window: Self.trendWindowSeconds)
            let decimated = decimate(samples, maxPoints: maxPoints)
            seriesList.append(GeomagSeries(element: GeomagElement(element), samples: decimated,
                                           stormIntervals: storms, recentChange: recentChange))
        }

        let covered: ClosedRange<Double>? = coveredHi >= coveredLo ? coveredLo...coveredHi : nil
        let fromCacheOnly = days.allSatisfy { $0.isFinal }
        let stationName = days.compactMap { $0.stationName }.last
        let source = days.compactMap { $0.source }.last
        return GeomagSeriesResult(observatoryCode: code.uppercased(), series: seriesList,
                                  requestedRange: requestedRange, coveredRange: covered,
                                  fromCacheOnly: fromCacheOnly, stationName: stationName, source: source)
    }

    /// Trailing window for the headline trend arrow: the field's trajectory over the last
    /// 30 minutes (kept separate from the storm window even though they currently agree).
    public static let trendWindowSeconds: Double = 30 * 60

    /// Net change between the latest sample and the finite sample nearest to `window`
    /// seconds before it — the field's trajectory over the trailing window.
    static func netChange(_ samples: [GeomagSample], window: Double) -> Double? {
        guard let last = samples.last else { return nil }
        let target = last.time - window
        guard let nearest = samples.min(by: { abs($0.time - target) < abs($1.time - target) }) else {
            return nil
        }
        return last.value - nearest.value
    }

    /// Min/max envelope decimation: preserves storm spikes that average/stride decimation
    /// would smooth away, while bounding the point count to ~`maxPoints`.
    static func decimate(_ samples: [GeomagSample], maxPoints: Int) -> [GeomagSample] {
        let n = samples.count
        guard n > maxPoints, maxPoints >= 4 else { return samples }

        let bucketCount = max(1, maxPoints / 2)
        var result: [GeomagSample] = []
        result.reserveCapacity(bucketCount * 2 + 2)
        result.append(samples[0])

        for bucket in 0..<bucketCount {
            let start = bucket * n / bucketCount
            let end = (bucket + 1) * n / bucketCount
            guard start < end else { continue }
            var minSample = samples[start]
            var maxSample = samples[start]
            for index in start..<end {
                let value = samples[index].value
                if value < minSample.value { minSample = samples[index] }
                if value > maxSample.value { maxSample = samples[index] }
            }
            if minSample.time <= maxSample.time {
                result.append(minSample)
                if maxSample.time != minSample.time { result.append(maxSample) }
            } else {
                result.append(maxSample)
                result.append(minSample)
            }
        }

        if let last = samples.last, last.time != result.last?.time {
            result.append(last)
        }
        return result
    }
}
