// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Retention caps for cached station data — the client-side mirror of the worker's
/// MAX_TIME / MAX_DATA_SIZE vars. The phone/Mac keep as much as the mirror serves; the
/// watch keeps just enough for its largest displayable range (1 month) plus slack.
public enum GeomagRetention {
    #if os(watchOS)
    public static let maxAge: TimeInterval = 35 * UTCDate.secondsPerDay
    public static let maxBytesPerStation: Int64 = 8 * 1_048_576
    #else
    public static let maxAge: TimeInterval = 366 * UTCDate.secondsPerDay
    public static let maxBytesPerStation: Int64 = 64 * 1_048_576
    #endif
}

/// On-disk cache of per-day geomagnetic records, shared across the app and its extensions
/// via the App Group container.
///
/// Layout: `<container>/GeomagCache3/<CODE>/<yyyy-MM-dd>.plist`, one binary-plist-encoded
/// `GeomagDay` per file. Per-day granularity is what makes "only fetch new data" cheap:
/// a finalized past day is a single file that never has to be re-downloaded.
///
/// The directory name is versioned: bump it when cached days become untrustworthy en masse
/// (v2: days wrongly finalized while incomplete; v3: HDZ days now normalized to XYZ with
/// the DECBAS baseline applied). Old directories are deleted on init.
public struct GeomagStore: Sendable {
    private let root: URL

    public init(root: URL = ObservatoryAppGroup.containerURL.appendingPathComponent("GeomagCache3", isDirectory: true)) {
        self.root = root
        // Sweep previous cache generations so stale/poisoned days can't linger.
        for legacyName in ["GeomagCache", "GeomagCache2"] {
            let legacy = ObservatoryAppGroup.containerURL.appendingPathComponent(legacyName, isDirectory: true)
            if FileManager.default.fileExists(atPath: legacy.path) {
                try? FileManager.default.removeItem(at: legacy)
            }
        }
        pruneAll()
    }

    // MARK: - Retention

    /// Apply the retention caps to one station: drop days older than the age limit, then —
    /// oldest first — until the station fits its byte budget. Filenames are yyyy-MM-dd, so
    /// lexicographic order is chronological.
    public func prune(code: String, now: Date = Date()) {
        let fm = FileManager.default
        let dir = directory(for: code)
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        let cutoffStamp = UTCDate.dayString(now.timeIntervalSince1970 - GeomagRetention.maxAge)

        var kept: [(name: String, size: Int64)] = []
        var total: Int64 = 0
        for name in names.filter({ $0.hasSuffix(".plist") }).sorted() {
            let url = dir.appendingPathComponent(name)
            if String(name.dropLast(6)) < cutoffStamp {
                try? fm.removeItem(at: url)
                continue
            }
            let size = ((try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
            kept.append((name, size))
            total += size
        }
        // Over budget: shed oldest days, always keeping the newest one.
        var index = 0
        while total > GeomagRetention.maxBytesPerStation, index < kept.count - 1 {
            try? fm.removeItem(at: dir.appendingPathComponent(kept[index].name))
            total -= kept[index].size
            index += 1
        }
    }

    /// Retention sweep across every cached station (run once at startup).
    public func pruneAll(now: Date = Date()) {
        guard let codes = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return }
        for code in codes where !code.hasPrefix(".") {
            prune(code: code, now: now)
        }
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
