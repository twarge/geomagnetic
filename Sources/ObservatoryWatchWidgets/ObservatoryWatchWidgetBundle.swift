// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0
//
// The watch complication set. Both share GeomagWidgetProvider (fixed to the 1-day window
// with a tight timeout, since complications run on a small budget) and the adaptive
// GeomagWidgetView.

import WidgetKit
import SwiftUI

private func watchProvider() -> GeomagWidgetProvider {
    GeomagWidgetProvider(range: .day, timeout: 10, refreshMinutes: 30)
}

/// Value-focused complication for the small families.
struct ObservatoryFieldComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ObservatoryFieldComplication", provider: watchProvider()) { entry in
            GeomagWidgetView(snapshot: entry.snapshot, style: .field)
        }
        .configurationDisplayName("Field Reading")
        .description("Latest field reading from your selected observatory.")
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryCorner])
    }
}

/// The large rectangular complication uses the same chart style as the watch app.
struct ObservatoryChartComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ObservatoryChartComplication", provider: watchProvider()) { entry in
            GeomagWidgetView(snapshot: entry.snapshot, style: .chart, dropsTopMargin: true)
        }
        .configurationDisplayName("Field Chart")
        .description("Recent field variation, storm highlights, and the latest reading.")
        .supportedFamilies([.accessoryRectangular])
        .contentMarginsDisabled()
    }
}

@main
struct ObservatoryWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        ObservatoryFieldComplication()
        ObservatoryChartComplication()
    }
}
