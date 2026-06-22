// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A single geomagnetic field element (IAGA-2002 component letter), e.g. H, D, Z, F, X, Y, G.
public struct GeomagElement: Hashable, Codable, Sendable, Identifiable {
    public let code: String   // single upper-case letter

    public init(_ code: String) {
        self.code = code.uppercased()
    }

    public var id: String { code }

    /// Reporting unit per the IAGA-2002 spec: D and I are angles in minutes of arc;
    /// everything else is a field strength in nanotesla.
    public var unit: String {
        switch code {
        case "D", "I": return "arcmin"
        default: return "nT"
        }
    }

    public var displayName: String {
        switch code {
        case "X": return "North (X)"
        case "Y": return "East (Y)"
        case "Z": return "Vertical (Z)"
        case "H": return "Horizontal (H)"
        case "D": return "Declination (D)"
        case "I": return "Inclination (I)"
        case "F": return "Total Field (F)"
        case "G": return "Delta-F (G)"
        case "S": return "Scalar (S)"
        default: return code
        }
    }

    /// Short label for compact UI (widgets, complications, legends).
    public var shortName: String { code }
}

/// An INTERMAGNET observatory. `latitude`/`longitude` are seed values from the bundled
/// directory; the precise values reported in each IAGA-2002 header take precedence once
/// data has been fetched.
public struct GeomagObservatory: Identifiable, Codable, Hashable, Sendable {
    public let code: String          // IAGA code, e.g. "FRD"
    public let name: String
    public let country: String
    public let latitude: Double      // geodetic, degrees north
    public let longitude: Double     // degrees east, normalized to [-180, 180]

    public init(code: String, name: String, country: String, latitude: Double, longitude: Double) {
        self.code = code.uppercased()
        self.name = name
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
    }

    public var id: String { code }
}

/// One UTC day of data for one observatory at a fixed cadence. This is the unit of
/// caching: past days are immutable once published, so they are fetched exactly once.
///
/// Values are stored column-major (one array per element) so plotting a subset of
/// elements is a direct slice. `Float.nan` marks a missing/flagged sample.
public struct GeomagDay: Codable, Sendable {
    public let observatoryCode: String
    public let dayStart: Double       // epoch seconds at 00:00:00 UTC
    public let cadence: Double        // seconds between samples (60 for 1-minute data)
    public let elements: [String]     // component letters, column order
    public let values: [[Float]]      // [elementIndex][sampleIndex]
    /// `true` once the day is in the past and known complete — never re-fetched.
    public let isFinal: Bool
    public let fetchedAt: Date
    // From the IAGA-2002 header (optional so older cache files still decode).
    public let stationName: String?   // e.g. "Fredericksburg, USA"
    public let source: String?        // operating institute, e.g. "USGS"

    public init(observatoryCode: String, dayStart: Double, cadence: Double,
                elements: [String], values: [[Float]], isFinal: Bool, fetchedAt: Date,
                stationName: String? = nil, source: String? = nil) {
        self.observatoryCode = observatoryCode
        self.dayStart = dayStart
        self.cadence = cadence
        self.elements = elements
        self.values = values
        self.isFinal = isFinal
        self.fetchedAt = fetchedAt
        self.stationName = stationName
        self.source = source
    }

    public var sampleCount: Int { values.first?.count ?? 0 }

    public var isEmpty: Bool { sampleCount == 0 }

    /// Epoch timestamp of sample `index`.
    public func time(at index: Int) -> Double { dayStart + Double(index) * cadence }

    /// Column index for an element letter, if present.
    public func columnIndex(of element: String) -> Int? {
        elements.firstIndex(of: element.uppercased())
    }
}

/// A timestamped scalar sample.
public struct GeomagSample: Sendable, Hashable {
    public let time: Double   // epoch seconds (UTC)
    public let value: Double

    public init(time: Double, value: Double) {
        self.time = time
        self.value = value
    }
}

/// One element's time series, possibly decimated for display. `stormIntervals` is computed
/// from the full-resolution samples (before decimation) so storm timing stays accurate.
public struct GeomagSeries: Sendable, Identifiable {
    public let element: GeomagElement
    public let samples: [GeomagSample]
    public let stormIntervals: [StormInterval]
    /// Net field change over the last 30 minutes of available data (latest minus the value
    /// ~30 min earlier), computed from full-resolution samples. nil if unknown.
    public let recentChange: Double?

    public init(element: GeomagElement, samples: [GeomagSample],
                stormIntervals: [StormInterval] = [], recentChange: Double? = nil) {
        self.element = element
        self.samples = samples
        self.stormIntervals = stormIntervals
        self.recentChange = recentChange
    }

    public var id: String { element.code }

    public var latest: GeomagSample? { samples.last }

    public var valueRange: ClosedRange<Double>? {
        let values = samples.map(\.value).filter(\.isFinite)
        guard let lo = values.min(), let hi = values.max() else { return nil }
        return lo...max(hi, lo)
    }
}

/// The result of resolving a view: the per-element series plus the actual covered time
/// span and a note on whether everything came from cache.
public struct GeomagSeriesResult: Sendable {
    public let observatoryCode: String
    public let series: [GeomagSeries]
    public let requestedRange: ClosedRange<Double>
    public let coveredRange: ClosedRange<Double>?
    public let fromCacheOnly: Bool
    public let stationName: String?   // from the IAGA-2002 header, when available
    public let source: String?        // operating institute, for attribution

    public init(observatoryCode: String, series: [GeomagSeries],
                requestedRange: ClosedRange<Double>, coveredRange: ClosedRange<Double>?,
                fromCacheOnly: Bool, stationName: String? = nil, source: String? = nil) {
        self.observatoryCode = observatoryCode
        self.series = series
        self.requestedRange = requestedRange
        self.coveredRange = coveredRange
        self.fromCacheOnly = fromCacheOnly
        self.stationName = stationName
        self.source = source
    }

    public var isEmpty: Bool { series.allSatisfy { $0.samples.isEmpty } }
}

/// Errors surfaced by the GIN client and repository.
public enum GeomagError: LocalizedError {
    case serviceError(String)
    case noData
    case badResponse
    case invalidObservatory(String)

    public var errorDescription: String? {
        switch self {
        case .serviceError(let message): return message
        case .noData: return "No data is available for this observatory and time range yet."
        case .badResponse: return "The data service returned an unexpected response."
        case .invalidObservatory(let code): return "Unknown observatory \"\(code)\"."
        }
    }
}
