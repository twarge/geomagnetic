// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Observatory — a cross-platform viewer for INTERMAGNET geomagnetic observatory data.
/// The app fetches only the time window in view, caches each UTC day, and never
/// re-downloads a finalized past day.
@main
struct ObservatoryApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        #if os(macOS)
        .defaultSize(width: 1_080, height: 720)
        #endif
    }
}
