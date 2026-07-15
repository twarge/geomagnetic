// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0
//
// One timeline provider shared by every widget kind and every complication, so the whole
// set is driven by a single bounded fetch.

import WidgetKit
import Foundation

struct GeomagEntry: TimelineEntry {
    let date: Date
    let snapshot: GeomagWidgetSnapshot
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
            let snapshot = await GeomagWidgetData.snapshot(range: effectiveRange, timeout: timeout, maxPoints: maxPoints, now: now)
            let entry = GeomagEntry(date: now, snapshot: snapshot)
            completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(refreshMinutes * 60))))
        }
    }
}
