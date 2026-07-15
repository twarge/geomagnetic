// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Client for the Edinburgh INTERMAGNET Geomagnetic Information Node (GIN) web service.
///
/// Mirrors the request the reference `download.py` builds, but fetches a contiguous run
/// of days in one call via `dataDuration`, then lets the caller split the response into
/// per-day cache entries.
public struct GINClient: Sendable {
    public enum Cadence: Int, Sendable {
        case minute = 1_440     // samples per day
        case second = 86_400

        public var seconds: Double { UTCDate.secondsPerDay / Double(rawValue) }
    }

    /// Base URL of the geomagnetic data service.
    ///
    /// Defaults to the **Observatory mirror** — a Cloudflare Worker (the `observatory-worker`
    /// repo) that caches INTERMAGNET data and rate-limits upstream access, so the app fleet
    /// (every iPhone/Watch) never hammers the GIN directly. The mirror speaks the GIN's
    /// `GetData` request and returns identical IAGA-2002 text, so nothing else here changes.
    ///
    /// Override with the `OBSERVATORY_BASE_URL` environment variable (set it in the Xcode
    /// scheme) to bypass the mirror — e.g. hit `ginDirectURL`, or a local `wrangler dev`.
    public static let baseURL: String = {
        if let override = ProcessInfo.processInfo.environment["OBSERVATORY_BASE_URL"],
           !override.isEmpty {
            return override
        }
        return "https://observatory-mirror.twarge.workers.dev/GIN_V1/GINServices"
    }()

    /// The upstream INTERMAGNET GIN that the mirror fronts — for reference or direct use.
    public static let ginDirectURL = "https://imag-data.bgs.ac.uk/GIN_V1/GINServices"

    /// Publication state: "adj-or-rep" returns the best of adjusted/reported/definitive,
    /// matching the reference downloader.
    public var publicationState: String
    public var session: URLSession

    public init(publicationState: String = "adj-or-rep", session: URLSession = .shared) {
        self.publicationState = publicationState
        self.session = session
    }

    /// Fetch `durationDays` of data starting at the UTC day `startDay`. Returns the raw
    /// IAGA-2002 text.
    public func fetchRaw(code: String, startDayEpoch: Double,
                         durationDays: Int, cadence: Cadence = .minute) async throws -> String {
        guard durationDays >= 1 else { throw GeomagError.badResponse }

        var components = URLComponents(string: Self.baseURL)!
        components.queryItems = [
            URLQueryItem(name: "Request", value: "GetData"),
            URLQueryItem(name: "format", value: "IAGA2002"),
            URLQueryItem(name: "testObsys", value: "0"),
            URLQueryItem(name: "observatoryIagaCode", value: code.uppercased()),
            URLQueryItem(name: "samplesPerDay", value: String(cadence.rawValue)),
            // Native orientation, normalized to XYZ locally (see normalizedToXYZ). Asking
            // the GIN to convert (orientation=XYZS) is subtly wrong for variation-mode HDZ
            // files: it ignores the DECBAS baseline declination, producing X/Y that jump
            // by thousands of nT against the observatory's absolute (adjusted) days.
            URLQueryItem(name: "orientation", value: "Native"),
            URLQueryItem(name: "publicationState", value: publicationState),
            URLQueryItem(name: "recordTermination", value: "UNIX"),
            URLQueryItem(name: "dataStartDate", value: UTCDate.dayString(startDayEpoch)),
            URLQueryItem(name: "dataDuration", value: String(durationDays)),
        ]
        guard let url = components.url else { throw GeomagError.badResponse }

        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("Observatory/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw GeomagError.serviceError("Data service returned HTTP \(http.statusCode).")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw GeomagError.badResponse
        }
        return text
    }

    /// A past day whose data is still incomplete keeps being re-fetched (data fills in as
    /// the observatory publishes); after this age it finalizes as-is, gaps and all.
    public static let finalizeIncompleteAfter: TimeInterval = 45 * UTCDate.secondsPerDay

    /// Fraction of a day's sample slots that must hold data before a past day is considered
    /// complete (and therefore immutable). Real "final" days routinely miss a few minutes.
    public static let finalCoverageFraction = 0.99

    /// Fetch and split a contiguous run of days into per-day records.
    ///
    /// `today` (a UTC day-start epoch) decides which produced days can be immutable: a day
    /// strictly before today is `isFinal` once its data is essentially complete (or once
    /// it is so old that what's there is all there will be).
    public func fetchDays(code: String, startDayEpoch: Double, durationDays: Int,
                          cadence: Cadence = .minute, today: Double,
                          now: Date) async throws -> [GeomagDay] {
        let text = try await fetchRaw(code: code, startDayEpoch: startDayEpoch,
                                      durationDays: durationDays, cadence: cadence)
        let parsed = try IAGA2002Parser.parse(text)
        return Self.bucketByDay(parsed, requestedCode: code, cadence: cadence,
                                today: today, now: now)
    }

    /// Convert an HDZ-oriented file to XYZ so every cached day carries the same element set
    /// regardless of how the observatory publishes (FRD: HDZF reported, XYZF adjusted).
    /// D is minutes of arc east — relative to the DECBAS baseline when one is declared —
    /// so X = H·cos(D₀+D), Y = H·sin(D₀+D). Files already in XYZ pass through untouched.
    static func normalizedToXYZ(_ parsed: ParsedIAGA) -> ParsedIAGA {
        guard let hIndex = parsed.elements.firstIndex(of: "H"),
              let dIndex = parsed.elements.firstIndex(of: "D"),
              !parsed.elements.contains("X"), !parsed.elements.contains("Y") else { return parsed }

        let baselineArcmin = (parsed.decbas ?? 0) / 10   // DECBAS is tenth-arcmin
        var normalized = parsed
        normalized.elements[hIndex] = "X"
        normalized.elements[dIndex] = "Y"
        normalized.rows = parsed.rows.map { row in
            var values = row.values
            if values.count > max(hIndex, dIndex) {
                let h = values[hIndex], d = values[dIndex]
                if h.isFinite, d.isFinite {
                    let radians = (Double(baselineArcmin) + Double(d)) / 60 * .pi / 180
                    values[hIndex] = h * Float(cos(radians))
                    values[dIndex] = h * Float(sin(radians))
                } else {
                    values[hIndex] = .nan
                    values[dIndex] = .nan
                }
            }
            return (time: row.time, values: values)
        }
        return normalized
    }

    /// Group parsed rows into per-UTC-day `GeomagDay` records on a fixed sample grid.
    /// Rows are placed at `round((time - dayStart) / cadence)`; missing grid slots are
    /// `Float.nan`, which keeps the time axis uniform and gaps visible.
    static func bucketByDay(_ rawParsed: ParsedIAGA, requestedCode: String,
                            cadence: Cadence, today: Double, now: Date) -> [GeomagDay] {
        let parsed = normalizedToXYZ(rawParsed)
        let elements = parsed.elements
        guard !elements.isEmpty else { return [] }

        let samplesPerDay = cadence.rawValue
        let cadenceSeconds = cadence.seconds
        let code = parsed.observatoryCode.isEmpty ? requestedCode.uppercased() : parsed.observatoryCode

        // dayStart -> [elementIndex][slot]
        var dayColumns: [Double: [[Float]]] = [:]

        for row in parsed.rows {
            let dayStart = UTCDate.startOfDay(row.time)
            let slot = Int(((row.time - dayStart) / cadenceSeconds).rounded())
            guard slot >= 0, slot < samplesPerDay else { continue }

            var columns = dayColumns[dayStart] ?? Array(
                repeating: Array(repeating: Float.nan, count: samplesPerDay),
                count: elements.count
            )
            let valueCount = min(row.values.count, elements.count)
            for elementIndex in 0..<valueCount {
                columns[elementIndex][slot] = row.values[elementIndex]
            }
            dayColumns[dayStart] = columns
        }

        return dayColumns.map { dayStart, columns in
            // A past day is immutable only once it's essentially complete: a slot counts as
            // covered when any element has a finite value there. Incomplete past days stay
            // refreshable (upstream fills them in over hours/days) until they age out.
            var covered = 0
            for slot in 0..<samplesPerDay where columns.contains(where: { $0[slot].isFinite }) {
                covered += 1
            }
            let complete = Double(covered) >= Double(samplesPerDay) * Self.finalCoverageFraction
            let agedOut = now.timeIntervalSince1970 - dayStart > Self.finalizeIncompleteAfter
            return GeomagDay(
                observatoryCode: code,
                dayStart: dayStart,
                cadence: cadenceSeconds,
                elements: elements,
                values: columns,
                isFinal: dayStart < today && (complete || agedOut),
                fetchedAt: now,
                stationName: parsed.stationName,
                source: parsed.source
            )
        }
        .sorted { $0.dayStart < $1.dayStart }
    }
}
