// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Carries the user's selections between their devices through iCloud's key-value store.
///
/// The settings stay in the App Group defaults, where `ObservatorySettings`, the widgets,
/// and the complications read them; this only copies a fixed list of keys in both
/// directions. Caches and fetched data never go through here.
///
/// Only the apps start it (once, at launch) — the widget extensions keep reading the App
/// Group defaults the app on the same device maintains.
@MainActor
public final class SettingsSync {
    public static let shared = SettingsSync()

    /// Posted on the main thread after values from another device were written into the
    /// defaults. `userInfo[changedKeysKey]` is the `[String]` of defaults keys that changed.
    public static let didPullNotification = Notification.Name("ObservatorySettingsSyncDidPull")
    public static let changedKeysKey = "keys"

    static let syncedKeys: [String] = [
        ObservatorySettings.Key.favorites,
        ObservatorySettings.Key.observatoryCode,
        ObservatorySettings.Key.elements,
        ObservatorySettings.Key.timeRange,
    ]

    private let defaults: UserDefaults
    private let store: NSUbiquitousKeyValueStore
    private var observers: [NSObjectProtocol] = []
    private var onPull: (@MainActor () -> Void)?
    /// True while `pull` is writing cloud values into the defaults; `push` stands down.
    private var isPulling = false

    init(defaults: UserDefaults = ObservatoryAppGroup.defaults, store: NSUbiquitousKeyValueStore = .default) {
        self.defaults = defaults
        self.store = store
    }

    /// Begins syncing. Without the iCloud entitlement, or signed out of iCloud, the store
    /// simply never reports or accepts anything.
    ///
    /// `onPull` runs after another device's values have been applied (before
    /// `didPullNotification` is posted) — the place to reload widget timelines.
    public func start(onPull: (@MainActor () -> Void)? = nil) {
        guard observers.isEmpty else { return }
        self.onPull = onPull
        observers.append(NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] notification in
            let keys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            MainActor.assumeIsolated { self?.pull(keys: keys ?? Self.syncedKeys) }
        })
        // `object: nil`: `ObservatoryAppGroup.defaults` hands out a fresh `UserDefaults`
        // instance per access, and the notification's object is whichever instance was
        // written through — never the one held here.
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.push() }
        })
        store.synchronize()
        pull(keys: Self.syncedKeys)
        // Then offer what this device has chosen and the cloud doesn't know yet (selections
        // made before sync existed). After the pull above, everything else already matches.
        push()
    }

    /// Cloud to device, for keys the cloud has a value for.
    ///
    /// Writing the defaults posts `UserDefaults.didChangeNotification` synchronously, which
    /// runs `push()` in the middle of the loop — while the keys not yet reached still hold
    /// this device's old values. Pushing then would overwrite the cloud's newer values for
    /// those keys with the stale local ones, so `push()` is held off until the loop is done.
    private func pull(keys: [String]) {
        var changed: [String] = []
        isPulling = true
        for key in keys where Self.syncedKeys.contains(key) {
            guard let value = store.object(forKey: key) as? NSObject,
                  (defaults.object(forKey: key) as? NSObject) != value
            else { continue }
            defaults.set(value, forKey: key)
            changed.append(key)
        }
        isPulling = false
        guard !changed.isEmpty else { return }
        onPull?()
        NotificationCenter.default.post(name: Self.didPullNotification, object: self,
                                        userInfo: [Self.changedKeysKey: changed])
    }

    /// Device to cloud, for keys the user has actually set. Nothing registers defaults for
    /// these keys (`ObservatorySettings` applies its fallbacks in code), so a value present
    /// in the suite is one that was chosen on this device or pulled from another.
    private func push() {
        guard !isPulling else { return }
        for key in Self.syncedKeys {
            guard let value = defaults.object(forKey: key) as? NSObject,
                  (store.object(forKey: key) as? NSObject) != value
            else { continue }
            store.set(value, forKey: key)
        }
    }
}
