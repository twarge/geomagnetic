// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Drives the detail screen: it asks the repository for exactly the selected time window
/// (the repository fetches only the days that aren't already cached) and exposes the
/// result to the plot. Element selection and the time range persist to the shared App
/// Group so the widgets and watch reflect the same view.
@MainActor
final class ObservatoryDetailViewModel: ObservableObject {
    let observatory: GeomagObservatory

    @Published var timeRange: ObservatoryTimeRange {
        didSet {
            guard timeRange != oldValue else { return }
            ObservatorySettings.timeRange = timeRange
            ObsWidgetRefresh.requestReload()   // widgets follow the app's chosen window
        }
    }

    /// Every element the latest result reported, in column order (drives the toggles).
    @Published private(set) var availableElements: [String] = []
    /// Elements the user chose to plot. Empty until the first result seeds a default.
    @Published var selectedElements: Set<String> = Set(ObservatorySettings.selectedElements) {
        didSet {
            guard selectedElements != oldValue else { return }
            ObservatorySettings.selectedElements = Array(selectedElements).sorted()
        }
    }

    @Published private(set) var result: GeomagSeriesResult?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?

    private let repository = GeomagRepository.shared

    init(observatory: GeomagObservatory) {
        self.observatory = observatory
        self.timeRange = ObservatorySettings.timeRange
    }

    /// Load the current window. Fetches all reported elements (they all arrive in one
    /// file, so this costs no extra network) and filters for display locally.
    func load(force: Bool = false, now: Date = Date()) async {
        isLoading = true
        errorMessage = nil
        let range = timeRange.dateRange(now: now)
        // Render whatever is already cached immediately — the plot hatches the stretch up
        // to now that hasn't loaded — then let the network fetch below replace it.
        if !force {
            let cached = await repository.cachedSeries(
                code: observatory.code, from: range.lowerBound, to: range.upperBound,
                elements: nil, maxPoints: timeRange.maxPoints)
            if !cached.isEmpty {
                self.result = cached
                availableElements = cached.series.map { $0.element.code }
                reconcileSelection()
            }
        }
        do {
            let result = try await repository.series(
                code: observatory.code, from: range.lowerBound, to: range.upperBound,
                elements: nil, maxPoints: timeRange.maxPoints, forceRefresh: force, now: now)
            self.result = result
            availableElements = result.series.map { $0.element.code }
            reconcileSelection()
            lastUpdated = now
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    /// Keep the selection valid against what's actually available, seeding a sensible
    /// default the first time (field components in nT, excluding the small Delta-F trace).
    private func reconcileSelection() {
        guard !availableElements.isEmpty else { return }
        let availableSet = Set(availableElements)
        let valid = selectedElements.intersection(availableSet)
        if valid.isEmpty {
            selectedElements = Self.defaultSelection(from: availableElements)
        } else if valid != selectedElements {
            selectedElements = valid
        }
    }

    /// Default to a single, autoscaled element so the field's variation is visible
    /// immediately (a shared axis across all components would render each one nearly flat).
    /// The header still shows every current value, and the chips add more traces.
    static func defaultSelection(from available: [String]) -> Set<String> {
        if let pick = ObservatoryElementPreference.primary(from: available) {
            return [pick]
        }
        return Set(available.prefix(1))
    }

    func paletteIndex(of element: String) -> Int {
        availableElements.firstIndex(of: element) ?? 0
    }

    /// Series to draw: available elements that are selected, colored by their stable
    /// column index so a trace keeps its color as others are toggled.
    var plotSeries: [ObsLineSeries] {
        guard let result else { return [] }
        return result.series.enumerated().compactMap { index, series in
            selectedElements.contains(series.element.code) ? series.obsLineSeries(index: index) : nil
        }
    }

    /// Always the *requested* window ending at the current time — not at the last
    /// successful fetch — so when the network is away the stretch between the end of the
    /// data record and "now" is part of the domain and renders as the no-data hatch.
    var fullXRange: ObsPlotRange? {
        let range = timeRange.dateRange(now: Date())
        return ObsPlotRange(minimum: range.lowerBound.timeIntervalSince1970,
                            maximum: range.upperBound.timeIntervalSince1970)
    }

    /// Latest finite reading per available element, for the header.
    var latestReadings: [LatestReading] {
        guard let result else { return [] }
        return result.series.compactMap { series in
            series.latest.map { LatestReading(element: series.element, sample: $0) }
        }
    }

    var yAxisLabel: String {
        let units = Set(plotSeries.compactMap { $0.unit })
        if units.count == 1, let unit = units.first { return unit }
        return "Value"
    }

    var hasData: Bool { !(result?.isEmpty ?? true) }
}

/// One element's most recent reading (Identifiable for `ForEach`).
struct LatestReading: Identifiable {
    let element: GeomagElement
    let sample: GeomagSample
    var id: String { element.code }
}
