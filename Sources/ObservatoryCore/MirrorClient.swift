// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Client for the Observatory mirror's compact `/v1` endpoints.
///
/// Where ``GINClient`` fetches whole UTC days of IAGA-2002 text (which the app then
/// decimates locally), the mirror's `/v1/series` returns data **already decimated**
/// server-side to a point budget, with storm bands attached — so a widget or watch
/// complication transfers a few KB instead of a whole day (or week, or month) of samples.
///
/// It deliberately returns the same ``GeomagSeriesResult`` the repository produces, so
/// callers stay agnostic to where the data came from.
///
/// Only available when ``GINClient/baseURL`` points at the mirror; with the
/// `OBSERVATORY_BASE_URL` dev override aimed at the raw GIN there is no `/v1`, so callers
/// should fall back to ``GeomagRepository``.
public struct MirrorClient: Sendable {
    public static let shared = MirrorClient()
    public var session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// The mirror origin derived from ``GINClient/baseURL`` (the worker root, no path), or
    /// `nil` when the base URL isn't a mirror — in which case `/v1` is unavailable.
    public static var origin: String? {
        let base = GINClient.baseURL
        guard let separator = base.range(of: "/GIN_V1/GINServices") else { return nil }
        return String(base[..<separator.lowerBound])
    }

    /// Server-decimated series for `[from, to]`, returned as a ``GeomagSeriesResult``.
    ///
    /// - Parameters:
    ///   - maxPoints: point budget per element (min/max envelope, like the local decimator).
    ///   - storms: ask the server to compute storm bands from full-resolution data.
    ///   - since: when set, the server returns only samples newer than this (delta updates).
    public func series(code: String, from: Date, to: Date,
                       elements: [String]? = nil, maxPoints: Int = 256,
                       storms: Bool = true, since: Date? = nil) async throws -> GeomagSeriesResult {
        guard let origin = Self.origin else {
            throw GeomagError.serviceError("The /v1 API is only available on the mirror.")
        }
        var components = URLComponents(string: origin + "/v1/series")!
        var items = [
            URLQueryItem(name: "obs", value: code.uppercased()),
            URLQueryItem(name: "from", value: epochString(from)),
            URLQueryItem(name: "to", value: epochString(to)),
            URLQueryItem(name: "max", value: String(maxPoints)),
        ]
        if storms { items.append(URLQueryItem(name: "storms", value: "1")) }
        if let elements, !elements.isEmpty {
            items.append(URLQueryItem(name: "elements", value: elements.joined(separator: ",")))
        }
        if let since { items.append(URLQueryItem(name: "since", value: epochString(since))) }
        components.queryItems = items
        guard let url = components.url else { throw GeomagError.badResponse }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Observatory/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw GeomagError.serviceError("Mirror returned HTTP \(http.statusCode).")
        }
        let payload = try JSONDecoder().decode(SeriesPayload.self, from: data)
        let lo = min(from.timeIntervalSince1970, to.timeIntervalSince1970)
        let hi = max(from.timeIntervalSince1970, to.timeIntervalSince1970)
        return payload.asResult(requestedRange: lo...hi)
    }

    private func epochString(_ date: Date) -> String {
        String(Int(date.timeIntervalSince1970.rounded()))
    }
}

// MARK: - Wire format (/v1/series JSON)

private struct SeriesPayload: Decodable {
    let obs: String
    let source: String?
    let stationName: String?
    let covered: [Double]?
    let series: [Element]

    struct Element: Decodable {
        let element: String
        let points: [[Double]]       // [[epochSeconds, value], …]
        let recentChange: Double?
        let storms: [Storm]?
    }

    struct Storm: Decodable {
        let start: Double
        let end: Double
        let peakDelta: Double
    }

    func asResult(requestedRange: ClosedRange<Double>) -> GeomagSeriesResult {
        let geomagSeries = series.map { element -> GeomagSeries in
            let samples = element.points.compactMap { pair -> GeomagSample? in
                guard pair.count >= 2 else { return nil }
                return GeomagSample(time: pair[0], value: pair[1])
            }
            // Reconstruct the category from peakDelta using the app's own thresholds, so the
            // mirror and app agree without depending on the wire-format's category string.
            let intervals = (element.storms ?? []).map { storm in
                StormInterval(start: storm.start, end: storm.end,
                              category: StormCategory(deltaNT: storm.peakDelta),
                              peakDelta: storm.peakDelta)
            }
            return GeomagSeries(element: GeomagElement(element.element), samples: samples,
                                stormIntervals: intervals, recentChange: element.recentChange)
        }
        let coveredRange: ClosedRange<Double>? = {
            guard let covered, covered.count == 2, covered[1] >= covered[0] else { return nil }
            return covered[0]...covered[1]
        }()
        return GeomagSeriesResult(observatoryCode: obs, series: geomagSeries,
                                  requestedRange: requestedRange, coveredRange: coveredRange,
                                  fromCacheOnly: false, stationName: stationName, source: source)
    }
}
