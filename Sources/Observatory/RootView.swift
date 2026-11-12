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
                // ~50% wider than the platform default minimum (~180pt), so code + name +
                // country + star fit without truncation.
                .navigationSplitViewColumnWidth(min: 270, ideal: 300)
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
        // Widget taps arrive as "geomagnetic://CODE?range=…": select that station (the range
        // is applied to settings first, so a freshly created detail opens on it) and make
        // sure the detail column is showing. Reuse an existing window rather than opening a
        // new one per tap.
        .onOpenURL { url in
            guard let link = GeomagDeepLink.parse(url) else { return }
            if let range = link.range { ObservatorySettings.timeRange = range }
            if Observatories.observatory(code: link.code) != nil {
                selection = link.code
            }
            preferredColumn = .detail
        }
        // Another device chose a different station: follow it. (The write-back in
        // onChange(of: selection) above stores the value just pulled, which is a no-op.)
        // Only when the station itself was pulled — a synced favorite or range must not
        // push the detail while the list is showing (selection is nil there on iPhone).
        .onReceive(NotificationCenter.default.publisher(for: SettingsSync.didPullNotification)) { note in
            let pulled = note.userInfo?[SettingsSync.changedKeysKey] as? [String] ?? []
            guard pulled.contains(ObservatorySettings.Key.observatoryCode) else { return }
            let code = ObservatorySettings.observatoryCode
            if code != selection, Observatories.observatory(code: code) != nil {
                selection = code
            }
        }
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
    }
}
