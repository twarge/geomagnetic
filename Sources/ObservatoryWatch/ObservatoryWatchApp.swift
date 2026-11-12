// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

@main
struct ObservatoryWatchApp: App {
    init() {
        // The watch app is standalone with its own App Group container, so it syncs its
        // selections through iCloud itself; pulled values reach the complications too.
        SettingsSync.shared.start { ObsWidgetRefresh.requestReload() }
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}
