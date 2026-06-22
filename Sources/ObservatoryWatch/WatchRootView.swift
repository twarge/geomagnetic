// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct WatchRootView: View {
    @StateObject private var model = WatchViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    chartCard
                    rangePicker
                    navigation
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle(model.code)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.load(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task(id: TaskKey(code: model.code, range: model.range)) { await model.load() }
        }
    }

    @ViewBuilder
    private var chartCard: some View {
        if model.hasData {
            NavigationLink {
                WatchPlotView(model: model)
            } label: {
                ObsFieldChart(series: model.primarySparkline,
                              stationCode: model.observatory.code,
                              latestValue: model.primary?.sample.value,
                              unit: model.primary?.element.unit,
                              trend: model.trend,
                              stormIntervals: model.stormIntervals,
                              showHeader: true)
                    .frame(height: 128)
                    .padding(8)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        } else if model.isLoading {
            ProgressView().frame(maxWidth: .infinity, minHeight: 128)
        } else {
            ContentUnavailableView("No Data", systemImage: "chart.xyaxis.line")
                .frame(minHeight: 128)
        }
    }

    private var rangePicker: some View {
        Picker("Range", selection: Binding(get: { model.range }, set: { model.setRange($0) })) {
            ForEach(ObservatoryTimeRange.allCases) { range in
                Text(range.longLabel).tag(range)
            }
        }
        .pickerStyle(.navigationLink)
    }

    private var navigation: some View {
        NavigationLink {
            WatchObservatoryListView(model: model)
        } label: {
            Label("Observatory", systemImage: "globe")
        }
    }
}

private struct TaskKey: Equatable {
    let code: String
    let range: ObservatoryTimeRange
}

struct WatchPlotView: View {
    @ObservedObject var model: WatchViewModel

    var body: some View {
        Group {
            if model.hasData {
                ObsLinePlotView(
                    series: model.plotSeries,
                    xAxis: .time(timeZone: .gmt),
                    yAxisLabel: "nT",
                    visibleXRange: .constant(nil),
                    visibleYRange: .constant(nil),
                    fullXRange: model.fullXRange)
                .padding(.vertical, 4)
            } else {
                ContentUnavailableView("No Data", systemImage: "chart.xyaxis.line")
            }
        }
        .navigationTitle("\(model.code) \(model.range.shortLabel)")
    }
}
