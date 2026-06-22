// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Searchable observatory picker with a Favorites section. Selection is a bound IAGA code
/// so `NavigationSplitView` drives the detail column.
struct ObservatoryListView: View {
    @Binding var selection: String?
    @State private var query = ""
    @State private var favorites = ObservatorySettings.favorites

    private var results: [GeomagObservatory] { Observatories.search(query) }

    private var favoriteObservatories: [GeomagObservatory] {
        favorites.compactMap { Observatories.observatory(code: $0) }
    }

    var body: some View {
        List(selection: $selection) {
            if query.isEmpty, !favoriteObservatories.isEmpty {
                Section("Favorites") {
                    ForEach(favoriteObservatories) { row($0) }
                }
            }
            Section(query.isEmpty ? "All Observatories" : "Results") {
                ForEach(results) { row($0) }
            }
        }
        .searchable(text: $query, prompt: "Code, name, or country")
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    private func row(_ observatory: GeomagObservatory) -> some View {
        HStack(spacing: 12) {
            Text(observatory.code)
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(observatory.name).lineLimit(1)
                Text(observatory.country)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button {
                ObservatorySettings.toggleFavorite(observatory.code)
                favorites = ObservatorySettings.favorites
            } label: {
                Image(systemName: favorites.contains(observatory.code) ? "star.fill" : "star")
                    .foregroundStyle(favorites.contains(observatory.code) ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(favorites.contains(observatory.code) ? "Remove favorite" : "Add favorite")
        }
        .tag(observatory.code)
    }
}
