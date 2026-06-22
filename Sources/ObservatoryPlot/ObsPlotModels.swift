// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0
//
// Plotting primitives ported from HiDeF's bounded-preview plotter. The rendering and
// pan/zoom logic are reused verbatim where possible; the HDF5 data plumbing is gone and
// the x-axis gained a time-aware mode (see ObsTimeAxis).

import SwiftUI

/// A single (x, y) sample in data space. For Observatory, `x` is epoch seconds (UTC).
struct ObsPlotPoint {
    let x: Double
    let y: Double
}

/// One line on the plot — typically one geomagnetic element.
struct ObsLineSeries: Identifiable {
    let index: Int          // drives the palette color
    let label: String
    let unit: String?
    let points: [ObsPlotPoint]

    var id: Int { index }
}

/// How the horizontal axis labels its ticks.
enum ObsXAxisKind: Equatable {
    /// Numeric values; `usesRelativeDisplay` shows an offset label plus small deltas.
    case numeric(usesRelativeDisplay: Bool, precision: Int?)
    /// Epoch-second timestamps formatted as wall-clock time in `timeZone`.
    case time(timeZone: TimeZone)
}

/// A closed numeric interval with tick generation and the pan/zoom math used by the plot.
/// Ported from HiDeF's `HDFPlotRange`.
struct ObsPlotRange: Hashable {
    let minimum: Double
    let maximum: Double

    var span: Double { max(0, maximum - minimum) }

    init(values: [Double]) {
        self.init(minimum: values.min() ?? 0, maximum: values.max() ?? 1)
    }

    init?(optionalValues values: [Double]) {
        guard let minimum = values.min(), let maximum = values.max() else { return nil }
        self.init(minimum: minimum, maximum: maximum)
    }

    init(minimum: Double, maximum: Double) {
        if minimum == maximum {
            self.minimum = minimum - 1
            self.maximum = maximum + 1
        } else {
            self.minimum = minimum
            self.maximum = maximum
        }
    }

    func ratio(for value: Double) -> Double {
        guard maximum > minimum else { return 0.5 }
        return min(1, max(0, (value - minimum) / (maximum - minimum)))
    }

    func unclampedRatio(for value: Double) -> Double {
        guard maximum > minimum else { return 0.5 }
        return (value - minimum) / (maximum - minimum)
    }

    func ticks(count: Int) -> [Double] {
        guard count > 1, maximum > minimum else { return [minimum] }

        let step = Self.niceStep(for: (maximum - minimum) / Double(count - 1))
        guard step.isFinite, step > 0 else { return [minimum, maximum] }

        let firstTick = (minimum / step).rounded(.up) * step
        let lastTick = (maximum / step).rounded(.down) * step
        let epsilon = step * 1e-10
        var ticks: [Double] = []
        var tick = firstTick
        while tick <= lastTick + epsilon, ticks.count < max(count * 3, count + 2) {
            ticks.append(Self.cleanedTick(tick, step: step))
            tick += step
        }

        if ticks.isEmpty {
            return [Self.cleanedTick((minimum + maximum) / 2, step: step)]
        }
        return ticks
    }

    private static func niceStep(for rawStep: Double) -> Double {
        guard rawStep.isFinite, rawStep > 0 else { return rawStep }

        let exponent = floor(log10(rawStep))
        let magnitude = pow(10, exponent)
        let fraction = rawStep / magnitude
        let niceFraction: Double
        if fraction <= 1 { niceFraction = 1 }
        else if fraction <= 2 { niceFraction = 2 }
        else if fraction <= 2.5 { niceFraction = 2.5 }
        else if fraction <= 5 { niceFraction = 5 }
        else { niceFraction = 10 }
        return niceFraction * magnitude
    }

    private static func cleanedTick(_ value: Double, step: Double) -> Double {
        guard value.isFinite, step.isFinite, step > 0 else { return value }
        let rounded = (value / step).rounded() * step
        return abs(rounded) < step * 1e-10 ? 0 : rounded
    }

    func shifted(by delta: Double, within fullRange: ObsPlotRange) -> ObsPlotRange {
        guard span < fullRange.span else { return fullRange }
        return ObsPlotRange(minimum: minimum + delta, maximum: maximum + delta)
            .clamped(to: fullRange)
    }

    func zoomed(by scale: Double, around anchorRatio: Double, within fullRange: ObsPlotRange) -> ObsPlotRange {
        guard scale.isFinite, scale > 0, fullRange.span > 0 else { return self }

        let cleanAnchor = min(1, max(0, anchorRatio))
        let cleanScale = min(64, max(0.015625, scale))
        let minimumSpan = max(fullRange.span / 1_000_000, .ulpOfOne)
        let nextSpan = min(fullRange.span, max(minimumSpan, span / cleanScale))
        let anchor = minimum + (span * cleanAnchor)
        let nextMinimum = anchor - (nextSpan * cleanAnchor)
        return ObsPlotRange(minimum: nextMinimum, maximum: nextMinimum + nextSpan)
            .clamped(to: fullRange)
    }

    func clamped(to fullRange: ObsPlotRange) -> ObsPlotRange {
        guard fullRange.span > 0 else { return fullRange }
        let currentSpan = min(max(span, .ulpOfOne), fullRange.span)
        let lowerBound = fullRange.minimum
        let upperBound = fullRange.maximum - currentSpan
        let nextMinimum = min(max(minimum, lowerBound), upperBound)
        return ObsPlotRange(minimum: nextMinimum, maximum: nextMinimum + currentSpan)
    }
}

/// A zoom/pan viewport: nil on an axis means "show the full extent".
struct ObsPlotViewport: Equatable {
    var xRange: ObsPlotRange?
    var yRange: ObsPlotRange?
}

/// Color palette for series, ported from HiDeF.
enum ObsPlotSeriesPalette {
    private static let colors: [Color] = [.accentColor, .green, .orange, .pink, .purple, .cyan]
    static func color(at index: Int) -> Color { colors[index % colors.count] }
}

/// Numeric tick/label formatting, ported from HiDeF's `HDFNumericValueFormatter`.
enum ObsNumberFormatter {
    static func string(_ value: Double, precision: Int? = nil) -> String {
        guard value.isFinite else { return String(describing: value) }

        let significantDigits = min(17, max(1, precision ?? 6))
        let absolute = abs(value)
        if precision == nil, absolute != 0, absolute < 0.001 || absolute >= 1_000_000 {
            return String(format: "%.*e", min(significantDigits, 6), value)
        }
        return String(format: "%.*g", significantDigits, value)
    }

    static func signedOffsetString(_ value: Double, precision: Int? = nil) -> String {
        let absoluteValue = abs(value)
        let prefix = value < 0 ? "-" : "+"
        return "\(prefix)\(string(absoluteValue, precision: precision))"
    }

    /// Compact value for badges/complications: thousands grouped, fixed fractional digits.
    static func compact(_ value: Double, fractionDigits: Int = 1) -> String {
        guard value.isFinite else { return "—" }
        return String(format: "%.\(fractionDigits)f", value)
    }
}
