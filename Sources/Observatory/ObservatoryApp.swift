// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Observatory — a cross-platform viewer for INTERMAGNET geomagnetic observatory data.
/// The app fetches only the time window in view, caches each UTC day, and never
/// re-downloads a finalized past day.
@main
struct ObservatoryApp: App {
    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
        }
        #if os(macOS)
        .defaultSize(width: 1_080, height: 720)
        #endif
        // ⌘N opens another window. macOS has this by default for a WindowGroup, but iPadOS
        // only shows a New Window key command when the app supplies one; replacing the
        // system "new item" group gives both platforms the same explicit command.
        .commands {
            CommandGroup(replacing: .newItem) {
                NewWindowCommand()
            }
        }
    }
}

/// "New Window ⌘N", shown only where the platform can actually open one (iPad, Mac —
/// not iPhone).
private struct NewWindowCommand: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

    var body: some View {
        if supportsMultipleWindows {
            Button("New Window") { openWindow(id: "main") }
                .keyboardShortcut("n", modifiers: .command)
        }
    }
}
