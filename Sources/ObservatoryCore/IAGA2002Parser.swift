// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Parsed contents of an IAGA-2002 file (the format the Edinburgh GIN serves).
public struct ParsedIAGA: Sendable {
    public var observatoryCode: String
    public var stationName: String?
    public var source: String?         // "Source of Data" — operating institute (for attribution)
    public var latitude: Double?
    public var longitude: Double?      // normalized to [-180, 180]
    public var elevation: Double?
    public var dataType: String?       // Definitive / Adjusted / Reported / Provisional / Variation
    public var elements: [String]      // component letters in column order
    public var rows: [(time: Double, values: [Float])]
}

/// Parser for IAGA-2002 timeseries text.
///
/// The format is a fixed-ish header of `Label   Value |` lines, then a `DATE TIME DOY ...`
/// column header, then whitespace-separated data rows. Missing samples use the 99999/88888
/// sentinels, which become `Float.nan`.
public enum IAGA2002Parser {
    /// Value at/above this magnitude is an IAGA missing-data sentinel (99999, 88888).
    /// Real geomagnetic elements never reach it (|F| < ~70000 nT, |D| < 10800 arcmin).
    static let missingSentinel: Float = 88_888

    public static func parse(_ text: String) throws -> ParsedIAGA {
        // The GIN returns an HTML error page on bad requests.
        let head = text.prefix(512).lowercased()
        if head.contains("<html") || head.contains("ginservices error") {
            throw GeomagError.serviceError(extractServiceError(text) ?? "The data service reported an error.")
        }

        var code: String?
        var stationName: String?
        var source: String?
        var latitude: Double?
        var longitude: Double?
        var elevation: Double?
        var dataType: String?
        var reported: String?
        var headerElements: [String]?

        var rows: [(time: Double, values: [Float])] = []
        rows.reserveCapacity(1_500)

        var sawColumnHeader = false

        text.enumerateLines { rawLine, _ in
            if sawColumnHeader {
                if let row = parseDataRow(rawLine) {
                    rows.append(row)
                }
                return
            }

            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return }

            // Column header marks the boundary between metadata and data.
            if trimmed.hasPrefix("DATE") && trimmed.contains("TIME") {
                headerElements = elementsFromColumnHeader(trimmed)
                sawColumnHeader = true
                return
            }

            // Header metadata line: " Label   Value   |"
            guard let (label, value) = headerKeyValue(rawLine) else { return }
            switch label.lowercased() {
            case "iaga code":            code = value.uppercased()
            case "station name":         stationName = value
            case "source of data":       source = value
            case "geodetic latitude":    latitude = Double(value)
            case "geodetic longitude":   longitude = Double(value).map(normalizeLongitude)
            case "elevation":            elevation = Double(value)
            case "data type":            dataType = value
            case "reported":             reported = value
            default:                     break
            }
        }

        // Prefer the column header's element letters; fall back to the "Reported" field.
        let elements = headerElements
            ?? reported.map { $0.map { String($0).uppercased() } }
            ?? []

        guard !rows.isEmpty else { throw GeomagError.noData }

        return ParsedIAGA(
            observatoryCode: code ?? "",
            stationName: stationName,
            source: source,
            latitude: latitude,
            longitude: longitude,
            elevation: elevation,
            dataType: dataType,
            elements: elements,
            rows: rows
        )
    }

    // MARK: - Line parsing

    /// Split a header line into (label, value), trimming the trailing `|`. The value
    /// column is delimited by the first run of 2+ spaces, which is robust to the small
    /// column-position variations seen across observatories.
    static func headerKeyValue(_ line: String) -> (String, String)? {
        var content = Substring(line)
        if let bar = content.lastIndex(of: "|") {
            content = content[..<bar]
        }
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }

        guard let sep = trimmed.range(of: "  ") else { return nil }
        let label = trimmed[..<sep.lowerBound].trimmingCharacters(in: .whitespaces)
        let value = trimmed[sep.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty, !value.isEmpty else { return nil }
        return (label, value)
    }

    /// Element letters from a `DATE TIME DOY FRDX FRDY FRDZ FRDG |` column header: the
    /// trailing letter of each component column (works for any IAGA-code length).
    static func elementsFromColumnHeader(_ line: String) -> [String] {
        let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "|" })
        guard tokens.count > 3 else { return [] }
        return tokens.dropFirst(3).compactMap { token in
            token.last.map { String($0).uppercased() }
        }
    }

    /// Parse a single data row into an epoch timestamp and its element values.
    static func parseDataRow(_ line: String) -> (time: Double, values: [Float])? {
        var fields: [Substring] = []
        fields.reserveCapacity(8)
        for token in line.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
            if token == "|" { continue }
            fields.append(token)
        }
        guard fields.count >= 4 else { return nil }

        guard let time = parseDateTime(date: fields[0], time: fields[1]) else { return nil }

        var values: [Float] = []
        values.reserveCapacity(fields.count - 3)
        for raw in fields[3...] {
            guard let v = Float(raw) else {
                values.append(.nan)
                continue
            }
            values.append((!v.isFinite || abs(v) >= missingSentinel) ? .nan : v)
        }
        return (time, values)
    }

    /// "2024-01-15" + "00:01:00.000" -> epoch seconds (UTC).
    static func parseDateTime(date: Substring, time: Substring) -> Double? {
        let d = date.split(separator: "-")
        let t = time.split(separator: ":")
        guard d.count == 3, t.count == 3,
              let year = Int(d[0]), let month = Int(d[1]), let day = Int(d[2]),
              let hour = Int(t[0]), let minute = Int(t[1]), let second = Double(t[2]) else {
            return nil
        }
        return UTCDate.epoch(year: year, month: month, day: day,
                             hour: hour, minute: minute, second: second)
    }

    // MARK: - Helpers

    static func normalizeLongitude(_ lon: Double) -> Double {
        var value = lon.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }
        if value < -180 { value += 360 }
        return value
    }

    private static func extractServiceError(_ text: String) -> String? {
        // The error page embeds the reason in "<em>...</em>".
        guard let open = text.range(of: "<em>"),
              let close = text.range(of: "</em>", range: open.upperBound..<text.endIndex) else {
            return nil
        }
        let message = text[open.upperBound..<close.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? nil : message
    }
}
