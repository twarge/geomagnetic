// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Resolved axis: the tick positions, a label for each, and an optional anchor label
/// (e.g. the date shared by all intraday ticks). Used by `ObsLinePlotView` for both the
/// numeric and time x-axes, and by the y-axis (numeric).
struct ObsAxisDescriptor {
    let ticks: [Double]
    let offsetLabel: String?
    private let labeler: (Double) -> String

    init(ticks: [Double], offsetLabel: String?, labeler: @escaping (Double) -> String) {
        self.ticks = ticks
        self.offsetLabel = offsetLabel
        self.labeler = labeler
    }

    func label(for value: Double) -> String { labeler(value) }

    /// Build the x-axis for a given kind.
    static func makeX(kind: ObsXAxisKind, range: ObsPlotRange, tickCount: Int) -> ObsAxisDescriptor {
        switch kind {
        case .numeric(let usesRelative, let precision):
            return numeric(range: range, tickCount: tickCount,
                           usesRelativeDisplay: usesRelative, precision: precision)
        case .time(let timeZone):
            return ObsTimeAxis.descriptor(range: range, target: tickCount, timeZone: timeZone)
        }
    }

    /// Numeric axis, ported from HiDeF's `HDFPlotXAxisDisplay`.
    static func numeric(range: ObsPlotRange, tickCount: Int,
                        usesRelativeDisplay: Bool, precision: Int?) -> ObsAxisDescriptor {
        if usesRelativeDisplay {
            let offset = range.minimum
            let ticks = ObsPlotRange(minimum: 0, maximum: range.span)
                .ticks(count: tickCount)
                .map { range.minimum + $0 }
            return ObsAxisDescriptor(
                ticks: ticks,
                offsetLabel: ObsNumberFormatter.signedOffsetString(offset, precision: precision),
                labeler: { ObsNumberFormatter.string($0 - offset, precision: precision) }
            )
        } else {
            return ObsAxisDescriptor(
                ticks: range.ticks(count: tickCount),
                offsetLabel: nil,
                labeler: { ObsNumberFormatter.string($0, precision: precision) }
            )
        }
    }
}

/// Time formatting that honors the device's "24-Hour Time" setting.
enum ObsClock {
    static var is24Hour: Bool {
        let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? ""
        return !template.contains("a")
    }

    /// Standard hour:minute label format, e.g. "06:00" / "18:00" (24h) or "6:00AM" (12h).
    static var hourMinuteFormat: String { is24Hour ? "HH:mm" : "h:mma" }

    /// Short hour-only label format for compact charts, e.g. "06" / "18" (24h) or "6AM" (12h).
    static var hourFormat: String { is24Hour ? "HH" : "ha" }
}

/// Time-aware x-axis: picks human-friendly tick spacing (seconds → years) and formats
/// the labels in the requested time zone.
enum ObsTimeAxis {
    private enum LabelStyle { case secs, time, day, month, year }

    private enum Kind {
        case seconds(Double)
        case day(Int)
        case month(Int)
        case year(Int)
    }

    private struct Candidate {
        let approxSeconds: Double
        let style: LabelStyle
        let kind: Kind
    }

    private static let candidates: [Candidate] = [
        .init(approxSeconds: 1,      style: .secs,  kind: .seconds(1)),
        .init(approxSeconds: 2,      style: .secs,  kind: .seconds(2)),
        .init(approxSeconds: 5,      style: .secs,  kind: .seconds(5)),
        .init(approxSeconds: 10,     style: .secs,  kind: .seconds(10)),
        .init(approxSeconds: 15,     style: .secs,  kind: .seconds(15)),
        .init(approxSeconds: 30,     style: .secs,  kind: .seconds(30)),
        .init(approxSeconds: 60,     style: .time,  kind: .seconds(60)),
        .init(approxSeconds: 120,    style: .time,  kind: .seconds(120)),
        .init(approxSeconds: 300,    style: .time,  kind: .seconds(300)),
        .init(approxSeconds: 600,    style: .time,  kind: .seconds(600)),
        .init(approxSeconds: 900,    style: .time,  kind: .seconds(900)),
        .init(approxSeconds: 1_800,  style: .time,  kind: .seconds(1_800)),
        .init(approxSeconds: 3_600,  style: .time,  kind: .seconds(3_600)),
        .init(approxSeconds: 7_200,  style: .time,  kind: .seconds(7_200)),
        .init(approxSeconds: 10_800, style: .time,  kind: .seconds(10_800)),
        .init(approxSeconds: 21_600, style: .time,  kind: .seconds(21_600)),
        .init(approxSeconds: 43_200, style: .time,  kind: .seconds(43_200)),
        .init(approxSeconds: 86_400, style: .day,   kind: .day(1)),
        .init(approxSeconds: 172_800, style: .day,  kind: .day(2)),
        .init(approxSeconds: 604_800, style: .day,  kind: .day(7)),
        .init(approxSeconds: 2_629_800, style: .month, kind: .month(1)),
        .init(approxSeconds: 7_889_400, style: .month, kind: .month(3)),
        .init(approxSeconds: 15_778_800, style: .month, kind: .month(6)),
        .init(approxSeconds: 31_557_600, style: .year, kind: .year(1)),
        .init(approxSeconds: 63_115_200, style: .year, kind: .year(2)),
        .init(approxSeconds: 157_788_000, style: .year, kind: .year(5)),
        .init(approxSeconds: 315_576_000, style: .year, kind: .year(10)),
    ]

    static func descriptor(range: ObsPlotRange, target: Int, timeZone: TimeZone) -> ObsAxisDescriptor {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let span = range.span
        guard span > 0, span.isFinite else {
            return ObsAxisDescriptor(ticks: [range.minimum], offsetLabel: nil,
                                     labeler: { format($0, style: .time, timeZone: timeZone) })
        }

        let desired = span / Double(max(1, target - 1))
        let candidate = candidates.first(where: { $0.approxSeconds >= desired }) ?? candidates.last!
        let ticks = generateTicks(kind: candidate.kind, range: range, calendar: calendar)
        let style = candidate.style

        let offsetLabel = anchorLabel(style: style, range: range,
                                      calendar: calendar, timeZone: timeZone)

        return ObsAxisDescriptor(ticks: ticks, offsetLabel: offsetLabel) { value in
            format(value, style: style, timeZone: timeZone)
        }
    }

    private static func generateTicks(kind: Kind, range: ObsPlotRange, calendar: Calendar) -> [Double] {
        let lower = range.minimum
        let upper = range.maximum
        var ticks: [Double] = []

        switch kind {
        case .seconds(let step):
            let dayStart = calendar.startOfDay(for: Date(timeIntervalSince1970: lower)).timeIntervalSince1970
            var t = dayStart + (((lower - dayStart) / step).rounded(.up)) * step
            while t <= upper + 0.001, ticks.count < 64 {
                if t >= lower { ticks.append(t) }
                t += step
            }
        case .day(let k):
            var date = calendar.startOfDay(for: Date(timeIntervalSince1970: lower))
            while date.timeIntervalSince1970 < lower {
                date = calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
            }
            while date.timeIntervalSince1970 <= upper + 0.001, ticks.count < 64 {
                ticks.append(date.timeIntervalSince1970)
                date = calendar.date(byAdding: .day, value: k, to: date) ?? date.addingTimeInterval(Double(k) * 86_400)
            }
        case .month(let m):
            var comps = calendar.dateComponents([.year, .month], from: Date(timeIntervalSince1970: lower))
            comps.day = 1
            var date = calendar.date(from: comps) ?? Date(timeIntervalSince1970: lower)
            while date.timeIntervalSince1970 < lower {
                date = calendar.date(byAdding: .month, value: 1, to: date) ?? date
            }
            while date.timeIntervalSince1970 <= upper + 0.001, ticks.count < 64 {
                ticks.append(date.timeIntervalSince1970)
                date = calendar.date(byAdding: .month, value: m, to: date) ?? date
            }
        case .year(let y):
            var comps = calendar.dateComponents([.year], from: Date(timeIntervalSince1970: lower))
            comps.month = 1
            comps.day = 1
            var date = calendar.date(from: comps) ?? Date(timeIntervalSince1970: lower)
            while date.timeIntervalSince1970 < lower {
                date = calendar.date(byAdding: .year, value: 1, to: date) ?? date
            }
            while date.timeIntervalSince1970 <= upper + 0.001, ticks.count < 64 {
                ticks.append(date.timeIntervalSince1970)
                date = calendar.date(byAdding: .year, value: y, to: date) ?? date
            }
        }

        return ticks.isEmpty ? [lower] : ticks
    }

    private static func anchorLabel(style: LabelStyle, range: ObsPlotRange,
                                    calendar: Calendar, timeZone: TimeZone) -> String? {
        let suffix = timeZone.identifier == "GMT" || timeZone.secondsFromGMT() == 0 ? "UTC" : timeZone.abbreviation() ?? ""
        switch style {
        case .secs, .time:
            // Intraday ticks: anchor to the start date.
            let dateLabel = format(range.minimum, style: .day, timeZone: timeZone, includeYear: true)
            return "\(dateLabel) \(suffix)".trimmingCharacters(in: .whitespaces)
        case .day:
            let startYear = calendar.component(.year, from: Date(timeIntervalSince1970: range.minimum))
            let endYear = calendar.component(.year, from: Date(timeIntervalSince1970: range.maximum))
            return startYear == endYear ? "\(startYear) \(suffix)".trimmingCharacters(in: .whitespaces) : suffix
        case .month, .year:
            return suffix.isEmpty ? nil : suffix
        }
    }

    // MARK: - Formatting

    private static func format(_ epoch: Double, style: LabelStyle,
                               timeZone: TimeZone, includeYear: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        switch style {
        case .secs:  formatter.dateFormat = ObsClock.is24Hour ? "HH:mm:ss" : "h:mm:ssa"
        case .time:  formatter.dateFormat = ObsClock.hourMinuteFormat
        case .day:   formatter.dateFormat = includeYear ? "yyyy-MM-dd" : "MMM d"
        case .month: formatter.dateFormat = "MMM yyyy"
        case .year:  formatter.dateFormat = "yyyy"
        }
        return formatter.string(from: Date(timeIntervalSince1970: epoch))
    }
}
