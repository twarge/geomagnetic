// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Observatory picker for the watch: favorites first, then the rest. Tapping selects and
/// pops back to the field view.
struct WatchObservatoryListView: View {
    @ObservedObject var model: WatchViewModel
    @Environment(\.dismiss) private var dismiss

    private var favorites: [GeomagObservatory] {
        ObservatorySettings.favorites.compactMap { Observatories.observatory(code: $0) }
    }

    private var others: [GeomagObservatory] {
        let favoriteCodes = Set(ObservatorySettings.favorites)
        return Observatories.all.filter { !favoriteCodes.contains($0.code) }
    }

    var body: some View {
        List {
            if !favorites.isEmpty {
                Section("Favorites") {
                    ForEach(favorites) { row($0) }
                }
            }
            Section("All") {
                ForEach(others) { row($0) }
            }
        }
        .navigationTitle("Observatory")
    }

    private func row(_ observatory: GeomagObservatory) -> some View {
        Button {
            model.select(observatory.code)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(observatory.code).font(.headline)
                    Text(observatory.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if observatory.code == model.code {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
    }
}
