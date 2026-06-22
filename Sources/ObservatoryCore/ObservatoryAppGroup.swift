// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Shared storage location and preferences used by the app, the iOS widgets, the
/// watchOS app, and the watch complications. Everything lives in an App Group so the
/// extensions read the same cache and the same "currently selected observatory" the
/// main app writes.
public enum ObservatoryAppGroup {
    /// App Group identifier. Must match the `com.apple.security.application-groups`
    /// entitlement on every target.
    public static let identifier = "group.com.twarge.observatory"

    /// Shared defaults for cross-process selection state.
    ///
    /// Falls back to `.standard` when the App Group container is unavailable, which
    /// happens for unsigned local/CI builds. The app still works; the processes just
    /// don't share state in that degraded mode.
    public static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    /// Root directory for all cached data, shared across processes when the App Group
    /// container is available.
    public static var containerURL: URL {
        let fileManager = FileManager.default
        if let url = fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        // Fallback for unsigned/local builds and tests.
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("Observatory", isDirectory: true)
    }
}
