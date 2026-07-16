// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Time windows offered throughout the app, widgets, and watch. Each maps to a duration
/// ending "now"; the repository fetches exactly the UTC days this window touches.
public enum ObservatoryTimeRange: String, CaseIterable, Codable, Sendable, Identifiable {
    case threeHours, sixHours, day, threeDays, week, month

    public var id: String { rawValue }

    public var duration: TimeInterval {
        switch self {
        case .threeHours: return 3 * 3_600
        case .sixHours:   return 6 * 3_600
        case .day:        return 24 * 3_600
        case .threeDays:  return 3 * 24 * 3_600
        case .week:       return 7 * 24 * 3_600
        case .month:      return 30 * 24 * 3_600
        }
    }

    public var shortLabel: String {
        switch self {
        case .threeHours: return "3H"
        case .sixHours:   return "6H"
        case .day:        return "1D"
        case .threeDays:  return "3D"
        case .week:       return "1W"
        case .month:      return "1M"
        }
    }

    public var longLabel: String {
        switch self {
        case .threeHours: return "3 Hours"
        case .sixHours:   return "6 Hours"
        case .day:        return "1 Day"
        case .threeDays:  return "3 Days"
        case .week:       return "1 Week"
        case .month:      return "1 Month"
        }
    }

    /// Closed date range ending at `now`.
    public func dateRange(now: Date = Date()) -> ClosedRange<Date> {
        now.addingTimeInterval(-duration)...now
    }

    /// A reasonable display point budget for this window (denser for short windows).
    public var maxPoints: Int {
        switch self {
        case .threeHours, .sixHours: return 720
        case .day:                   return 1_024
        case .threeDays, .week:      return 1_500
        case .month:                 return 2_000
        }
    }
}

/// Shared preference for the single "headline" element shown on the watch, in widgets, and
/// as the app's default plotted trace. F (total field) leads, then horizontal intensity,
/// then the Cartesian components — falling back so observatories that don't report F still
/// get a sensible primary.
public enum ObservatoryElementPreference {
    public static let order = ["F", "H", "X", "Z", "Y", "G", "D", "I"]

    public static func primary(from available: [String]) -> String? {
        let set = Set(available.map { $0.uppercased() })
        return order.first(where: { set.contains($0) }) ?? available.first?.uppercased()
    }
}

/// Cross-process selection state, persisted in the App Group defaults so the widgets and
/// the watch render the same observatory the user last looked at in the app.
public enum ObservatorySettings {
    private enum Key {
        static let observatoryCode = "selectedObservatoryCode"
        static let timeRange = "selectedTimeRange"
        static let elements = "selectedElements"
        static let favorites = "favoriteObservatoryCodes"
    }

    public static var observatoryCode: String {
        get { ObservatoryAppGroup.defaults.string(forKey: Key.observatoryCode) ?? Observatories.default.code }
        set { ObservatoryAppGroup.defaults.set(newValue.uppercased(), forKey: Key.observatoryCode) }
    }

    public static var observatory: GeomagObservatory {
        Observatories.observatory(code: observatoryCode) ?? Observatories.default
    }

    public static var timeRange: ObservatoryTimeRange {
        get {
            guard let raw = ObservatoryAppGroup.defaults.string(forKey: Key.timeRange),
                  let value = ObservatoryTimeRange(rawValue: raw) else { return .day }
            return value
        }
        set { ObservatoryAppGroup.defaults.set(newValue.rawValue, forKey: Key.timeRange) }
    }

    /// Elements the user has chosen to plot. Empty means "all available".
    public static var selectedElements: [String] {
        get { ObservatoryAppGroup.defaults.stringArray(forKey: Key.elements) ?? [] }
        set { ObservatoryAppGroup.defaults.set(newValue, forKey: Key.elements) }
    }

    public static var favorites: [String] {
        get { ObservatoryAppGroup.defaults.stringArray(forKey: Key.favorites) ?? [Observatories.default.code] }
        set { ObservatoryAppGroup.defaults.set(newValue, forKey: Key.favorites) }
    }

    public static func toggleFavorite(_ code: String) {
        let code = code.uppercased()
        var list = favorites
        if let index = list.firstIndex(of: code) {
            list.remove(at: index)
        } else {
            list.append(code)
        }
        favorites = list
    }

    public static func isFavorite(_ code: String) -> Bool {
        favorites.contains(code.uppercased())
    }
}

/// Deep link carried by every widget/complication ("geomagnetic://FRD?range=week") so a tap
/// opens the app showing the same observatory and window. On macOS the URL is what makes a
/// widget click actually present a window (plain activation shows nothing when none exist).
public enum GeomagDeepLink {
    public static let scheme = "geomagnetic"

    public static func url(code: String, range: ObservatoryTimeRange) -> URL? {
        URL(string: "\(scheme)://\(code.uppercased())?range=\(range.rawValue)")
    }

    /// (station code, range) from a deep link; nil if the URL isn't ours.
    public static func parse(_ url: URL) -> (code: String, range: ObservatoryTimeRange?)? {
        guard url.scheme?.lowercased() == scheme, let host = url.host, !host.isEmpty else { return nil }
        let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "range" })?.value
        return (host.uppercased(), raw.flatMap(ObservatoryTimeRange.init(rawValue:)))
    }
}
