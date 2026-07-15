// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Sidebar of observatories + detail plot. `NavigationSplitView` adapts to a single
/// push-navigation column on iPhone and a two-column layout on iPad/Mac.
struct RootView: View {
    @State private var selection: String? = ObservatorySettings.observatoryCode
    // On iPhone, open straight to the plot for the last-viewed observatory; the list is a
    // swipe/back away.
    @State private var preferredColumn: NavigationSplitViewColumn = .detail

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $preferredColumn) {
            ObservatoryListView(selection: $selection)
                .navigationTitle("Observatories")
        } detail: {
            NavigationStack {
                if let code = selection, let observatory = Observatories.observatory(code: code) {
                    ObservatoryDetailView(observatory: observatory)
                        .id(code)
                } else {
                    ContentUnavailableView("Select an Observatory",
                                           systemImage: "globe",
                                           description: Text("Choose a station to view its geomagnetic field."))
                }
            }
        }
        .onChange(of: selection) { _, newValue in
            if let newValue {
                ObservatorySettings.observatoryCode = newValue
                ObsWidgetRefresh.requestReload()   // widgets follow the selected observatory
            }
        }
    }
}
