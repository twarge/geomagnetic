// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0
//
// The iOS / macOS widget set. All three share GeomagWidgetProvider (one bounded fetch per
// timeline) and the adaptive GeomagWidgetView, differing only in style and families.

import WidgetKit
import SwiftUI

/// Headline reading + recent trace. Works as a home-screen tile and lock-screen accessory.
struct ObservatoryFieldWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ObservatoryFieldWidget", provider: GeomagWidgetProvider()) { entry in
            GeomagWidgetView(snapshot: entry.snapshot, style: .field)
        }
        .configurationDisplayName("Field Reading")
        .description("Latest field reading and recent trace from your selected observatory.")
        .supportedFamilies(Self.families)
    }

    static var families: [WidgetFamily] {
        #if os(iOS)
        // accessoryRectangular is served by the chart widget so it gets the full chart style.
        [.systemSmall, .systemMedium, .accessoryCircular, .accessoryInline]
        #else
        [.systemSmall, .systemMedium]
        #endif
    }
}

/// Sparkline-dominant variation chart.
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
        [.systemSmall, .systemMedium, .accessoryRectangular]
        #else
        [.systemSmall, .systemMedium]
        #endif
    }
}

/// Grid of every reported component's current value.
struct ObservatoryComponentsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ObservatoryComponentsWidget", provider: GeomagWidgetProvider()) { entry in
            GeomagWidgetView(snapshot: entry.snapshot, style: .components)
        }
        .configurationDisplayName("All Components")
        .description("Current readings for every component (X / Y / Z / F …).")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
