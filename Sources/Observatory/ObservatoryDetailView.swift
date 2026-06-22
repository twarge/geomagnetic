// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// The detail screen: header readings, a time-range picker, element toggles, and the
/// interactive plot. Loads exactly the visible window through the repository.
struct ObservatoryDetailView: View {
    @StateObject private var model: ObservatoryDetailViewModel
    @State private var visibleXRange: ObsPlotRange?
    @State private var visibleYRange: ObsPlotRange?
    @State private var isFavorite: Bool

    init(observatory: GeomagObservatory) {
        _model = StateObject(wrappedValue: ObservatoryDetailViewModel(observatory: observatory))
        _isFavorite = State(initialValue: ObservatorySettings.isFavorite(observatory.code))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            rangePicker
            if !model.availableElements.isEmpty { elementChips }
            plot
            footer
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(model.observatory.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbarContent }
        .task(id: model.timeRange) { await model.load() }
        .onChange(of: model.timeRange) { _, _ in resetViewport() }
        #if os(iOS)
        .refreshable { await model.load(force: true) }
        #endif
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(model.observatory.code) · \(model.observatory.country) · \(coordinateText)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !model.latestReadings.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(model.latestReadings) { reading in
                            readingView(reading.element, reading.sample)
                        }
                    }
                }
            }
        }
    }

    private func readingView(_ element: GeomagElement, _ sample: GeomagSample) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(element.code)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ObsPlotSeriesPalette.color(at: model.paletteIndex(of: element.code)))
            Text(ObsNumberFormatter.compact(sample.value, fractionDigits: 1))
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
            Text(element.unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var coordinateText: String {
        let lat = String(format: "%.1f°%@", abs(model.observatory.latitude), model.observatory.latitude >= 0 ? "N" : "S")
        let lon = String(format: "%.1f°%@", abs(model.observatory.longitude), model.observatory.longitude >= 0 ? "E" : "W")
        return "\(lat) \(lon)"
    }

    // MARK: - Controls

    private var rangePicker: some View {
        Picker("Time Range", selection: $model.timeRange) {
            ForEach(ObservatoryTimeRange.allCases) { range in
                Text(range.shortLabel).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var elementChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.availableElements, id: \.self) { code in
                    let selected = model.selectedElements.contains(code)
                    let color = ObsPlotSeriesPalette.color(at: model.paletteIndex(of: code))
                    Button {
                        model.toggle(code)
                    } label: {
                        Text(code)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selected ? color.opacity(0.22) : Color.secondary.opacity(0.12),
                                        in: Capsule())
                            .foregroundStyle(selected ? color : .secondary)
                            .overlay(Capsule().stroke(selected ? color : .clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(GeomagElement(code).displayName), \(selected ? "shown" : "hidden")")
                }
            }
            .padding(.vertical, 1)
        }
    }

    // MARK: - Plot

    private var plot: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.06))

            if model.hasData {
                ObsLinePlotView(
                    series: model.plotSeries,
                    xAxis: .time(timeZone: .gmt),
                    yAxisLabel: model.yAxisLabel,
                    visibleXRange: $visibleXRange,
                    visibleYRange: $visibleYRange,
                    fullXRange: model.fullXRange
                )
                .padding(6)
            } else if model.isLoading {
                ProgressView("Loading \(model.timeRange.longLabel)…")
            } else if let message = model.errorMessage {
                ContentUnavailableView {
                    Label("Couldn’t Load Data", systemImage: "antenna.radiowaves.left.and.right.slash")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await model.load(force: true) } }
                }
            } else {
                ContentUnavailableView("No Data Available",
                                       systemImage: "chart.xyaxis.line",
                                       description: Text("No published data for this window yet."))
            }

            if model.isLoading, model.hasData {
                ProgressView()
                    .padding(8)
                    .background(.regularMaterial, in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if let updated = model.lastUpdated {
                Label(updated.formatted(date: .omitted, time: .shortened), systemImage: "clock")
            }
            if model.result?.fromCacheOnly == true {
                Label("Cached", systemImage: "internaldrive")
            }
            Spacer()
            Text("Drag to zoom · double-tap to reset")
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                ObservatorySettings.toggleFavorite(model.observatory.code)
                isFavorite = ObservatorySettings.isFavorite(model.observatory.code)
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
            }
            .accessibilityLabel(isFavorite ? "Remove favorite" : "Add favorite")

            Button {
                Task { await model.load(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel("Refresh")
            .disabled(model.isLoading)
        }
    }

    private func resetViewport() {
        visibleXRange = nil
        visibleYRange = nil
    }
}
