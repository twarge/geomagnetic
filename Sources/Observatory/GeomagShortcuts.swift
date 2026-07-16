// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0
//
// Registers CurrentFieldIntent with Siri / Shortcuts / Spotlight, so questions like
// "What's the total magnetic field at Fredericksburg in Geomagnetic?" get a spoken answer.
// Phrases must mention the app name; station and component slots resolve via the
// StationEntity query and the FieldComponent enum.

import AppIntents

struct GeomagShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CurrentFieldIntent(),
            // Siri allows at most one parameter slot per phrase; the other parameter
            // falls back to its default (component: total field) or gets asked.
            phrases: [
                "What's the magnetic field in \(.applicationName)",
                "Get the magnetic field from \(.applicationName)",
                "What's the magnetic field at \(\.$station) in \(.applicationName)",
                "Get the field at \(\.$station) from \(.applicationName)",
                "What's the \(\.$component) in \(.applicationName)",
            ],
            shortTitle: "Magnetic Field",
            systemImageName: "waveform.path.ecg"
        )
    }
}
