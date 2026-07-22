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
    @State private var autoRangeTask: Task<Void, Never>?
    /// Set by automatic (zoom-driven) range switches so the user's view survives the
    /// reload — the gesture continues smoothly and the fetch fills in around it. Manual
    /// picker changes leave this false and reset the viewport as before.
    @State private var preserveViewportOnRangeChange = false
    /// Span at the previous auto-range evaluation; a step *down* requires the span to have
    /// shrunk (a real zoom-in). Without this, panning back toward "now" stepped the range
    /// down, discarding the loaded window and re-loading it on the next pan left.
    @State private var previousEvaluatedSpan: Double?

    init(observatory: GeomagObservatory) {
        _model = StateObject(wrappedValue: ObservatoryDetailViewModel(observatory: observatory))
        _isFavorite = State(initialValue: ObservatorySettings.isFavorite(observatory.code))
    }

    /// Wide windows (iPad, resized Mac windows, Stage Manager) put the pickers beside the
    /// measurements; narrow ones stack them beneath.
    @State private var layoutWidth: CGFloat = 0
    private var isWideLayout: Bool { layoutWidth >= 640 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isWideLayout {
                HStack(alignment: .top, spacing: 16) {
                    header
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 8) {
                        rangePicker.fixedSize()
                        if !model.availableElements.isEmpty { elementPicker.fixedSize() }
                    }
                }
            } else {
                header
                rangePicker
                if !model.availableElements.isEmpty { elementPicker }
            }
            plot
            attribution
            footer
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            layoutWidth = width
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(model.observatory.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbarContent }
        // Load, then keep the view alive: refresh every 5 minutes (matching the repository's
        // staleness window) so new readings appear — and, when the network is away, so the
        // domain's "now" edge advances and the no-data hatch visibly grows.
        .task(id: model.timeRange) {
            await model.load()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled else { break }
                await model.load()
            }
        }
        // A widget tap for the station that's already on screen: jump to the tapped range
        // (RootView handles selection; a new detail picks the range up from settings).
        .onOpenURL { url in
            guard let link = GeomagDeepLink.parse(url),
                  link.code == model.observatory.code,
                  let range = link.range else { return }
            model.timeRange = range
        }
        .onChange(of: model.timeRange) { _, _ in
            if preserveViewportOnRangeChange {
                preserveViewportOnRangeChange = false
            } else {
                resetViewport()
                previousEvaluatedSpan = nil
            }
        }
        .onChange(of: visibleXRange) { _, newValue in scheduleAutoRange(for: newValue) }
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

    /// Single-element selection as a segmented control, matching the time-range picker.
    /// (One autoscaled trace at a time — a shared axis would flatten every component.)
    private var elementPicker: some View {
        Picker("Element", selection: Binding(
            get: {
                model.availableElements.first(where: { model.selectedElements.contains($0) })
                    ?? model.availableElements.first ?? ""
            },
            set: { model.selectedElements = [$0] })) {
            ForEach(model.availableElements, id: \.self) { code in
                Text(code).tag(code)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: - Plot

    private var plot: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.06))

            if model.hasData {
                ObsLinePlotView(
                    series: model.plotSeries,
                    xAxis: .time(timeZone: .current),
                    yAxisLabel: model.yAxisLabel,
                    visibleXRange: $visibleXRange,
                    visibleYRange: $visibleYRange,
                    fullXRange: model.fullXRange,
                    xZoomLimit: zoomOutLimit
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

    // MARK: - Attribution

    /// INTERMAGNET's conditions of use (CC BY-NC 4.0) ask that the operating institute and
    /// INTERMAGNET be credited; the wording follows their suggested acknowledgement.
    private var attribution: some View {
        // No fixedSize here: a vertically-fixed wrapping Text answers the window's
        // minimum-size probe (width 0) with its one-glyph-per-line height, forcing an
        // absurd minimum window height on macOS. Plain Text in a VStack wraps fine.
        VStack(alignment: .leading, spacing: 1) {
            Text(stationCredit)
            Text("Made available through [INTERMAGNET](https://intermagnet.org), promoting high standards of magnetic observatory practice · CC BY-NC 4.0")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .tint(.secondary)
    }

    private var stationCredit: String {
        let station = model.result?.stationName ?? model.observatory.name
        if let source = model.result?.source, !source.isEmpty {
            return "Data collected at \(station) (\(model.observatory.code)) by \(source)."
        }
        return "Data collected at \(station) (\(model.observatory.code))."
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

    // MARK: - Automatic time-range switching (pinch to change timescale)

    /// How far past the loaded window a pinch-out may go (× the window). Gives the gesture
    /// room to exceed the window, which is the signal to step up to a longer range.
    private static let zoomOutHeadroom = 1.6

    private var zoomOutLimit: ObsPlotRange? {
        guard let window = model.fullXRange, window.span > 0 else { return nil }
        return ObsPlotRange(minimum: window.maximum - window.span * Self.zoomOutHeadroom,
                            maximum: window.maximum)
    }

    /// Debounce so a switch fires once per gesture pause, not on every pinch tick.
    private func scheduleAutoRange(for visible: ObsPlotRange?) {
        autoRangeTask?.cancel()
        guard let visible else { return }
        autoRangeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            applyAutoRange(visible: visible)
        }
    }

    /// Pick the time range that fits what the user zoomed to. Zooming out past the loaded
    /// window steps up one range; zooming in near the trailing edge steps down to the
    /// smallest range containing the view. Both keep the viewport — the fetch fills the
    /// hatched not-yet-loaded margin (zoom out) or refills the same view at higher density
    /// (zoom in); only picking a range by hand resets the view.
    private func applyAutoRange(visible: ObsPlotRange) {
        guard !model.isLoading, let window = model.fullXRange, window.span > 0,
              visible.span.isFinite, visible.span > 0 else { return }
        let ranges = ObservatoryTimeRange.allCases   // ascending by duration
        let current = model.timeRange
        let spanShrank = previousEvaluatedSpan.map { visible.span < $0 * 0.98 } ?? false
        previousEvaluatedSpan = visible.span

        // Pinched out beyond the loaded data, or panned left into the unloaded (hatched)
        // margin → one step up; the longer range's fetch fills the view in place.
        let pannedIntoPast = visible.minimum < window.minimum - window.span * 0.01
        if visible.span > window.span * 1.02 || pannedIntoPast {
            guard let index = ranges.firstIndex(of: current), index + 1 < ranges.count else { return }
            preserveViewportOnRangeChange = true
            model.timeRange = ranges[index + 1]
            return
        }

        // Pinched in on the trailing slice → smallest range that still contains the view
        // (measured back from the window's end, since ranges always end at "now"). Only an
        // actual zoom-in qualifies: panning must never shrink the loaded window, or a
        // left-right pan cycle re-loads the same history over and over.
        guard spanShrank else { return }
        let required = window.maximum - visible.minimum
        if let target = ranges.first(where: { $0.duration >= required * 0.999 }),
           target.duration < current.duration {
            preserveViewportOnRangeChange = true
            model.timeRange = target
        }
    }
}
