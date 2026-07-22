// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Retention caps for cached station data. A minute-cadence day (4 elements) is ~45 KB on
/// disk, so a month per station is ~1.3 MB. The overall budget is enforced by evicting the
/// least-recently-used *station*; only when a single station remains do its oldest days go.
public enum GeomagRetention {
    #if os(watchOS)
    public static let maxAge: TimeInterval = 35 * UTCDate.secondsPerDay
    /// ≈ one station × one month, plus slack.
    public static let maxTotalBytes: Int64 = 1_572_864
    #else
    public static let maxAge: TimeInterval = 366 * UTCDate.secondsPerDay
    /// ≈ two stations × one month, plus slack.
    public static let maxTotalBytes: Int64 = 3_145_728
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

    /// Age-prune one station (drop days beyond the retention age), then re-apply the global
    /// byte budget. Filenames are yyyy-MM-dd, so lexicographic order is chronological.
    public func prune(code: String, now: Date = Date()) {
        let fm = FileManager.default
        let dir = directory(for: code)
        if let names = try? fm.contentsOfDirectory(atPath: dir.path) {
            let cutoffStamp = UTCDate.dayString(now.timeIntervalSince1970 - GeomagRetention.maxAge)
            for name in names where name.hasSuffix(".plist") && String(name.dropLast(6)) < cutoffStamp {
                try? fm.removeItem(at: dir.appendingPathComponent(name))
            }
        }
        enforceGlobalBudget()
    }

    /// Retention sweep across every cached station (run once at startup).
    public func pruneAll(now: Date = Date()) {
        guard let codes = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return }
        for code in codes where !code.hasPrefix(".") {
            let dir = directory(for: code)
            if let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
                let cutoffStamp = UTCDate.dayString(now.timeIntervalSince1970 - GeomagRetention.maxAge)
                for name in names where name.hasSuffix(".plist") && String(name.dropLast(6)) < cutoffStamp {
                    try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
                }
            }
        }
        enforceGlobalBudget()
    }

    /// Keep the whole cache inside `GeomagRetention.maxTotalBytes`: evict the
    /// least-recently-*fetched* station outright while more than one remains, then — if a
    /// single station alone still exceeds the budget — shed its oldest days. Recency is the
    /// newest file modification time in a station's directory, which tracks actual use (the
    /// station being viewed refreshes its "today" file constantly).
    private func enforceGlobalBudget() {
        let fm = FileManager.default
        guard let codes = try? fm.contentsOfDirectory(atPath: root.path) else { return }

        struct Station { let code: String; var bytes: Int64; var lastUsed: Date }
        var stations: [Station] = []
        for code in codes where !code.hasPrefix(".") {
            let dir = directory(for: code)
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            var bytes: Int64 = 0
            var newest = Date.distantPast
            for name in names {
                let attrs = try? fm.attributesOfItem(atPath: dir.appendingPathComponent(name).path)
                bytes += ((attrs?[.size] as? NSNumber)?.int64Value ?? 0)
                if let modified = attrs?[.modificationDate] as? Date, modified > newest {
                    newest = modified
                }
            }
            stations.append(Station(code: code, bytes: bytes, lastUsed: newest))
        }

        var total = stations.reduce(0) { $0 + $1.bytes }
        stations.sort { $0.lastUsed < $1.lastUsed }   // least recently used first

        // Evict whole stations, LRU first, never the most recently used one.
        while total > GeomagRetention.maxTotalBytes, stations.count > 1 {
            let victim = stations.removeFirst()
            try? fm.removeItem(at: directory(for: victim.code))
            total -= victim.bytes
        }

        // A single station over budget on its own: shed oldest days, keep the newest.
        if total > GeomagRetention.maxTotalBytes, let last = stations.first {
            let dir = directory(for: last.code)
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
            let days = names.filter { $0.hasSuffix(".plist") }.sorted()
            for name in days.dropLast() {
                guard total > GeomagRetention.maxTotalBytes else { break }
                let url = dir.appendingPathComponent(name)
                let size = ((try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
                try? fm.removeItem(at: url)
                total -= size
            }
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
