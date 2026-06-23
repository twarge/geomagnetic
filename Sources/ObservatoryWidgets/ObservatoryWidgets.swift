// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0
//
// The iOS / macOS widget set: a Field Chart (home-screen tiles plus the rectangular and
// inline lock-screen accessories) and, on iOS, a Field Reading circular lock-screen
// accessory. Both share GeomagWidgetProvider (one bounded fetch per timeline) and the
// adaptive GeomagWidgetView.

import WidgetKit
import SwiftUI

/// Sparkline-dominant variation chart. Serves the home-screen tiles and, on iOS, the
/// rectangular and inline lock-screen accessories.
struct ObservatoryChartWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ObservatoryChartWidget", provider: GeomagWidgetProvider()) { entry in
            GeomagWidgetView(snapshot: entry.snapshot, style: .chart)
        }
        .configurationDisplayName("Field Chart")
        .description("Recent variation of the field over your selected time window.")
        .supportedFamilies(Self.families)
    }

    static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline]
        #else
        [.systemSmall, .systemMedium]
        #endif
    }
}

#if os(iOS)
/// The latest reading on the circular lock-screen dial ("FRD F" over the value).
struct ObservatoryFieldWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ObservatoryFieldWidget", provider: GeomagWidgetProvider()) { entry in
            GeomagWidgetView(snapshot: entry.snapshot, style: .field)
        }
        .configurationDisplayName("Field Reading")
        .description("Latest field reading from your selected observatory.")
        .supportedFamilies([.accessoryCircular])
    }
}
#endif
