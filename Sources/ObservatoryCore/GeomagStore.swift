// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// On-disk cache of per-day geomagnetic records, shared across the app and its extensions
/// via the App Group container.
///
/// Layout: `<container>/GeomagCache/<CODE>/<yyyy-MM-dd>.plist`, one binary-plist-encoded
/// `GeomagDay` per file. Per-day granularity is what makes "only fetch new data" cheap:
/// a finalized past day is a single file that never has to be re-downloaded.
public struct GeomagStore: Sendable {
    private let root: URL

    public init(root: URL = ObservatoryAppGroup.containerURL.appendingPathComponent("GeomagCache", isDirectory: true)) {
        self.root = root
    }

    private func directory(for code: String) -> URL {
        root.appendingPathComponent(code.uppercased(), isDirectory: true)
    }

    private func fileURL(code: String, dayStart: Double) -> URL {
        directory(for: code).appendingPathComponent(UTCDate.dayString(dayStart) + ".plist")
    }

    public func loadDay(code: String, dayStart: Double) -> GeomagDay? {
        let url = fileURL(code: code, dayStart: dayStart)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? PropertyListDecoder().decode(GeomagDay.self, from: data)
    }

    public func saveDay(_ day: GeomagDay) {
        let directory = directory(for: day.observatoryCode)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(day) else { return }
        try? data.write(to: fileURL(code: day.observatoryCode, dayStart: day.dayStart), options: .atomic)
    }

    /// Day-start epochs already cached for an observatory (used for diagnostics / cleanup).
    public func cachedDayStarts(code: String) -> [Double] {
        let directory = directory(for: code)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        return names.compactMap { name in
            guard name.hasSuffix(".plist") else { return nil }
            let stamp = String(name.dropLast(6))   // strip ".plist"
            let parts = stamp.split(separator: "-")
            guard parts.count == 3,
                  let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
                return nil
            }
            return UTCDate.epoch(year: year, month: month, day: day)
        }
        .sorted()
    }

    /// Most recent cached day for an observatory, newest first scan.
    public func mostRecentDay(code: String) -> GeomagDay? {
        for dayStart in cachedDayStarts(code: code).reversed() {
            if let day = loadDay(code: code, dayStart: dayStart), !day.isEmpty {
                return day
            }
        }
        return nil
    }

    /// Total bytes used by the cache (for a settings/“clear cache” screen).
    public func cacheSizeBytes() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += Int64(size)
        }
        return total
    }

    public func clear() {
        try? FileManager.default.removeItem(at: root)
    }
}
