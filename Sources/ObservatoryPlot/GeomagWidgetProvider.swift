// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0
//
// One timeline provider shared by every widget kind and every complication, so the whole
// set is driven by a single bounded fetch.

import WidgetKit
import AppIntents
import Foundation

struct GeomagEntry: TimelineEntry {
    let date: Date
    let snapshot: GeomagWidgetSnapshot
    /// Scroll-pair state (see ObsWidgetScrollMemory.entries): seconds of extra data drawn
    /// left of the window, and — on the pre-scroll entry only — the previous refresh's
    /// window end and reading.
    var scrollback: Double = 0
    var displayWindowEnd: Double? = nil
    var displayValue: Double? = nil
}

/// What the previous timeline displayed, per widget kind + configuration — recalled on the
/// next refresh so the new stretch of data can scroll in from exactly that state.
enum ObsWidgetScrollMemory {
    struct Prior {
        let windowEnd: Double
        let value: Double?
        let element: String?
    }

    /// New-data stretches outside these bounds jump instead of scrolling: below, the shift
    /// would be sub-pixel noise; above (e.g. the first refresh after a night), scrolling
    /// would mean fetching a large extra stretch just for a transition.
    private static let minSeconds: Double = 90
    private static let maxWindowFraction = 0.25

    private static func key(kind: String, code: String, range: ObservatoryTimeRange, element: String?) -> String {
        "widgetScrollPrior.\(kind).\(code.uppercased()).\(range.rawValue).\(element ?? "auto")"
    }

    /// The stored prior, when animating from it is worthwhile. `now - prior.windowEnd` is
    /// the lookback to add to the snapshot fetch.
    static func prior(kind: String?, code: String, range: ObservatoryTimeRange,
                      element: String? = nil, now: Date) -> Prior? {
        guard let kind,
              let stored = ObservatoryAppGroup.defaults.dictionary(forKey: key(kind: kind, code: code, range: range, element: element)),
              let end = stored["end"] as? Double else { return nil }
        let delta = now.timeIntervalSince1970 - end
        guard delta >= minSeconds, delta <= range.duration * maxWindowFraction else { return nil }
        return Prior(windowEnd: end, value: stored["value"] as? Double, element: stored["element"] as? String)
    }

    static func store(kind: String?, code: String, element: String? = nil, snapshot: GeomagWidgetSnapshot) {
        guard let kind, let end = snapshot.windowEnd else { return }
        var stored: [String: Any] = ["end": end]
        if let value = snapshot.primaryValue { stored["value"] = value }
        if let elementCode = snapshot.primaryElement?.code { stored["element"] = elementCode }
        ObservatoryAppGroup.defaults.set(stored, forKey: key(kind: kind, code: code, range: snapshot.range, element: element))
    }

    /// The refresh's timeline entries: normally one. With a usable prior, a pair sharing
    /// the snapshot: the first re-creates what was already on screen (previous window
    /// position and reading) over the new, wider drawing; the second, a minute later, is
    /// that same drawing shifted to the new window. The shift and the reading are the only
    /// differences, so WidgetKit animates them — the new stretch scrolls in while the
    /// digits roll — over ObsScrollTransition's eased two seconds.
    static func entries(for snapshot: GeomagWidgetSnapshot, prior: Prior?, now: Date) -> [GeomagEntry] {
        guard let prior, let windowEnd = snapshot.windowEnd,
              snapshot.hasData, !snapshot.isPlaceholder,
              prior.element == nil || prior.element == snapshot.primaryElement?.code,
              windowEnd > prior.windowEnd else {
            return [GeomagEntry(date: now, snapshot: snapshot)]
        }
        let scrollback = windowEnd - prior.windowEnd
        return [GeomagEntry(date: now, snapshot: snapshot, scrollback: scrollback,
                            displayWindowEnd: prior.windowEnd, displayValue: prior.value),
                GeomagEntry(date: now.addingTimeInterval(ObsScrollTransition.phaseGap),
                            snapshot: snapshot, scrollback: scrollback)]
    }
}

/// Ask WidgetKit to rebuild every widget/complication timeline on this device. The apps call
/// it when the user changes the observatory or time range — and the watch app after a
/// successful fetch — so glanceable surfaces track the app instead of waiting out their
/// scheduled refresh. (Reloads are budgeted by the system; tying them to explicit user
/// actions keeps us comfortably inside it.)
enum ObsWidgetRefresh {
    static func requestReload() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

struct GeomagWidgetProvider: TimelineProvider {
    /// nil follows the app's last-chosen range; a fixed value (e.g. complications) overrides.
    var range: ObservatoryTimeRange?
    var timeout: Double = 18
    var refreshMinutes: Double = 20
    /// Sparkline resolution. Small by default to keep the transfer (and the watch radio)
    /// light; the larger home-screen chart tiles raise it for denser traces.
    var maxPoints: Int = 80
    /// Non-nil opts this widget into animated refreshes (the scroll pair); the string
    /// keys the per-kind memory of what the previous timeline displayed.
    var scrollKind: String? = nil

    private var effectiveRange: ObservatoryTimeRange { range ?? ObservatorySettings.timeRange }

    func placeholder(in context: Context) -> GeomagEntry {
        GeomagEntry(date: Date(), snapshot: GeomagWidgetData.placeholder(range: effectiveRange))
    }

    func getSnapshot(in context: Context, completion: @escaping (GeomagEntry) -> Void) {
        if context.isPreview {
            completion(GeomagEntry(date: Date(), snapshot: GeomagWidgetData.placeholder(range: effectiveRange)))
            return
        }
        Task {
            let snapshot = await GeomagWidgetData.snapshot(range: effectiveRange, timeout: timeout, maxPoints: maxPoints)
            completion(GeomagEntry(date: Date(), snapshot: snapshot))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GeomagEntry>) -> Void) {
        Task {
            let now = Date()
            let code = ObservatorySettings.observatoryCode
            let range = effectiveRange
            let prior = ObsWidgetScrollMemory.prior(kind: scrollKind, code: code, range: range, now: now)
            let snapshot = await GeomagWidgetData.snapshot(
                code: code, range: range, timeout: timeout, maxPoints: maxPoints,
                lookback: prior.map { now.timeIntervalSince1970 - $0.windowEnd } ?? 0, now: now)
            ObsWidgetScrollMemory.store(kind: scrollKind, code: code, snapshot: snapshot)
            completion(Timeline(entries: ObsWidgetScrollMemory.entries(for: snapshot, prior: prior, now: now),
                                policy: .after(now.addingTimeInterval(Self.nextRefresh(after: snapshot, normal: refreshMinutes)))))
        }
    }

    /// Stale or empty snapshots retry sooner than the normal cadence, so a complication
    /// recovers within minutes of connectivity returning instead of waiting a full cycle.
    static func nextRefresh(after snapshot: GeomagWidgetSnapshot, normal minutes: Double) -> TimeInterval {
        (snapshot.isStale || !snapshot.hasData ? min(minutes, 10) : minutes) * 60
    }
}

/// Intent-configured variant (iOS/macOS home-screen and desktop widgets): right-click →
/// Edit Widget picks the observatory and field component; unset parameters follow the app.
struct GeomagConfiguredProvider: AppIntentTimelineProvider {
    var timeout: Double = 18
    var refreshMinutes: Double = 20
    var maxPoints: Int = 240
    /// Non-nil opts this widget into animated refreshes (see GeomagWidgetProvider.scrollKind).
    var scrollKind: String? = nil

    func placeholder(in context: Context) -> GeomagEntry {
        GeomagEntry(date: Date(), snapshot: GeomagWidgetData.placeholder(range: ObservatorySettings.timeRange))
    }

    func snapshot(for configuration: ObservatoryWidgetConfigIntent, in context: Context) async -> GeomagEntry {
        if context.isPreview {
            return placeholder(in: context)
        }
        return await entry(for: configuration)
    }

    func timeline(for configuration: ObservatoryWidgetConfigIntent, in context: Context) async -> Timeline<GeomagEntry> {
        let now = Date()
        let code = configuration.station?.id ?? ObservatorySettings.observatoryCode
        let range = configuration.range ?? ObservatorySettings.timeRange
        let element = configuration.component?.rawValue
        let prior = ObsWidgetScrollMemory.prior(kind: scrollKind, code: code, range: range,
                                                element: element, now: now)
        let snapshot = await GeomagWidgetData.snapshot(
            code: code, range: range, timeout: timeout, maxPoints: maxPoints,
            preferredElement: element,
            lookback: prior.map { now.timeIntervalSince1970 - $0.windowEnd } ?? 0, now: now)
        ObsWidgetScrollMemory.store(kind: scrollKind, code: code, element: element, snapshot: snapshot)
        let next = GeomagWidgetProvider.nextRefresh(after: snapshot, normal: refreshMinutes)
        return Timeline(entries: ObsWidgetScrollMemory.entries(for: snapshot, prior: prior, now: now),
                        policy: .after(now.addingTimeInterval(next)))
    }

    #if os(watchOS)
    // Required by the watchOS flavor of the protocol (complication gallery presets); the
    // watch currently ships static complications, so a single follow-the-app entry suffices.
    func recommendations() -> [AppIntentRecommendation<ObservatoryWidgetConfigIntent>] {
        [AppIntentRecommendation(intent: ObservatoryWidgetConfigIntent(), description: "Field Chart")]
    }
    #endif

    private func entry(for configuration: ObservatoryWidgetConfigIntent) async -> GeomagEntry {
        let now = Date()
        let snapshot = await GeomagWidgetData.snapshot(
            code: configuration.station?.id ?? ObservatorySettings.observatoryCode,
            range: configuration.range ?? ObservatorySettings.timeRange,
            timeout: timeout,
            maxPoints: maxPoints,
            preferredElement: configuration.component?.rawValue,
            now: now)
        return GeomagEntry(date: now, snapshot: snapshot)
    }
}
