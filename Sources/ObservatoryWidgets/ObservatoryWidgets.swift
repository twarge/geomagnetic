// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0
//
// The iOS / macOS widget set: a Field Chart (home-screen/desktop tiles in three sizes plus
// the rectangular and inline lock-screen accessories) and, on iOS, a Field Reading circular
// lock-screen accessory. Both are user-configurable (right-click / long-press → Edit
// Widget) to a specific observatory and field component; unset parameters follow the app.

import WidgetKit
import SwiftUI

/// Sparkline-dominant variation chart. The large family is simply a double-height canvas
/// for the same chart, so a day's structure is easier to read at a glance.
struct ObservatoryChartWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ObservatoryChartWidget",
                               intent: ObservatoryWidgetConfigIntent.self,
                               provider: GeomagConfiguredProvider(scrollKind: "chart")) { entry in
            GeomagWidgetView(snapshot: entry.snapshot, style: .chart,
                             scrollbackSeconds: entry.scrollback,
                             displayWindowEnd: entry.displayWindowEnd,
                             displayValue: entry.displayValue)
        }
        .configurationDisplayName("Field Chart")
        .description("Recent variation of the field over your selected time window.")
        .supportedFamilies(Self.families)
    }

    static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline]
        #else
        [.systemSmall, .systemMedium, .systemLarge]
        #endif
    }
}

/// Every reported component with its value and hourly trend, one line each:
/// "F 50,083.42 nT   −30 nT/hr".
struct ObservatoryComponentsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ObservatoryComponentsWidget",
                               intent: ObservatoryWidgetConfigIntent.self,
                               provider: GeomagConfiguredProvider(maxPoints: 80)) { entry in
            GeomagWidgetView(snapshot: entry.snapshot, style: .components)
        }
        .configurationDisplayName("All Components")
        .description("Current value and hourly trend for every component.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#if os(iOS)
/// The latest reading on the circular lock-screen dial ("FRD F" over the value).
struct ObservatoryFieldWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ObservatoryFieldWidget",
                               intent: ObservatoryWidgetConfigIntent.self,
                               provider: GeomagConfiguredProvider(maxPoints: 80, scrollKind: "field")) { entry in
            GeomagWidgetView(snapshot: entry.snapshot, style: .field,
                             scrollbackSeconds: entry.scrollback,
                             displayWindowEnd: entry.displayWindowEnd,
                             displayValue: entry.displayValue)
        }
        .configurationDisplayName("Field Reading")
        .description("Latest field reading from your selected observatory.")
        .supportedFamilies([.accessoryCircular])
    }
}
#endif
