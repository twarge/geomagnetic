// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct WatchRootView: View {
    @StateObject private var model = WatchViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    // Station name, kept tight to the first reading line below it.
                    Text(model.stationName)
                        .font(.title3).fontWeight(.semibold)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .padding(.horizontal, 4)
                        .padding(.bottom, -2)

                    content
                }
                .padding(.horizontal, 4)
            }
            // Load now, then keep refreshing every 5 minutes while the view lives (the
            // repository's own staleness window makes repeats cheap).
            .task(id: TaskKey(code: model.code, range: model.range)) {
                await model.load()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(300))
                    guard !Task.isCancelled else { break }
                    await model.load()
                }
            }
            // .task(id:) does NOT re-fire when the app is re-activated with an unchanged
            // id — without this, reopening the app (e.g. from a complication tap) showed
            // stale data until a manual Refresh.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await model.load() }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.hasData {
            // F on top, then X / Y / Z, in a scrollable stack.
            ForEach(model.elementGraphs) { graph in
                graphCard(graph)
            }
            attributionView
        } else if model.isLoading {
            ProgressView().frame(maxWidth: .infinity, minHeight: 120)
        } else {
            ContentUnavailableView("No Data", systemImage: "chart.xyaxis.line").frame(minHeight: 120)
        }
        rangePicker
        observatoryLink
        reloadButton
    }

    // A plain, non-interactive graph card (tapping does nothing for now).
    private func graphCard(_ graph: WatchElementGraph) -> some View {
        // Anchor the axis to the current window (ending now) so cached data — the last we
        // fetched before losing signal — sits at its true time and the un-covered stretch
        // hatches, instead of stale data being stretched to look current.
        let window = model.range.dateRange()
        return ObsFieldChart(series: graph.sparkline,
                      stationCode: model.code,
                      element: graph.element.code,
                      latestValue: graph.value,
                      unit: graph.element.unit,
                      trend: graph.trend,
                      stormIntervals: graph.storms,
                      showHeader: true,
                      headerFont: .footnote,
                      windowStart: window.lowerBound.timeIntervalSince1970,
                      windowEnd: window.upperBound.timeIntervalSince1970)
            .frame(height: 104)
            .padding(8)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // Complete data-source text, on as many lines as it needs, below the graphs.
    private var attributionView: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let source = model.sourceText {
                Text(source)
            }
            Text("Via INTERMAGNET · intermagnet.org · CC BY-NC 4.0")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private var rangePicker: some View {
        Picker("Range", selection: Binding(get: { model.range }, set: { model.setRange($0) })) {
            ForEach(ObservatoryTimeRange.allCases) { range in
                Text(range.longLabel).tag(range)
            }
        }
        .pickerStyle(.navigationLink)
        // Span the leading-aligned stack so the control centers like the Refresh button.
        .frame(maxWidth: .infinity)
    }

    private var observatoryLink: some View {
        NavigationLink {
            WatchObservatoryListView(model: model)
        } label: {
            Label("Observatory", systemImage: "globe")
                .frame(maxWidth: .infinity)
        }
    }

    private var reloadButton: some View {
        Button {
            Task { await model.load(force: true) }
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.isLoading)
    }
}

private struct TaskKey: Equatable {
    let code: String
    let range: ObservatoryTimeRange
}
