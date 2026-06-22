// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Magnetic-storm severity, classified by the field change (peak-to-peak) within a rolling
/// 30-minute window.
public enum StormCategory: Int, Sendable, Comparable, CaseIterable {
    case quiet = 0
    case moderate      // 50–100 nT
    case intense       // 100–250 nT
    case superStorm    // > 250 nT

    public init(deltaNT: Double) {
        switch deltaNT {
        case ..<StormThresholds.moderate: self = .quiet
        case ..<StormThresholds.intense: self = .moderate
        case ..<StormThresholds.super: self = .intense
        default: self = .superStorm
        }
    }

    public var label: String {
        switch self {
        case .quiet: return ""
        case .moderate: return "Moderate Storm"
        case .intense: return "Intense Storm"
        case .superStorm: return "Super Storm"
        }
    }

    public static func < (lhs: StormCategory, rhs: StormCategory) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum StormThresholds {
    public static let moderate: Double = 50
    public static let intense: Double = 100
    public static let `super`: Double = 250
}

/// A contiguous interval during which the rolling 30-minute field change qualifies as a
/// storm, tagged with the most severe category reached.
public struct StormInterval: Sendable, Identifiable {
    public let start: Double      // epoch seconds
    public let end: Double        // epoch seconds
    public let category: StormCategory
    public let peakDelta: Double  // largest 30-min peak-to-peak in the interval (nT)

    public var id: Double { start }

    public init(start: Double, end: Double, category: StormCategory, peakDelta: Double) {
        self.start = start
        self.end = end
        self.category = category
        self.peakDelta = peakDelta
    }
}

public enum StormDetector {
    public static let windowSeconds: Double = 30 * 60

    /// Find storm intervals in time-sorted, finite samples. For each sample the field change
    /// is the peak-to-peak over the trailing 30-minute window; contiguous samples whose
    /// change is ≥ the moderate threshold merge into one interval (categorized by its peak).
    ///
    /// Sliding window min/max are maintained with monotonic deques, so this is O(n).
    public static func intervals(from samples: [GeomagSample],
                                 window: Double = windowSeconds) -> [StormInterval] {
        guard samples.count > 1 else { return [] }

        var maxDeque: [Int] = []   // indices, values non-increasing front→back
        var minDeque: [Int] = []   // indices, values non-decreasing front→back
        var left = 0
        var intervals: [StormInterval] = []
        var startTime: Double?
        var endTime: Double = 0
        var peak: Double = 0

        for right in 0..<samples.count {
            let time = samples[right].time
            let value = samples[right].value

            while let last = maxDeque.last, samples[last].value <= value { maxDeque.removeLast() }
            maxDeque.append(right)
            while let last = minDeque.last, samples[last].value >= value { minDeque.removeLast() }
            minDeque.append(right)

            while samples[left].time < time - window {
                if maxDeque.first == left { maxDeque.removeFirst() }
                if minDeque.first == left { minDeque.removeFirst() }
                left += 1
            }

            let delta = samples[maxDeque[0]].value - samples[minDeque[0]].value
            if delta >= StormThresholds.moderate {
                if startTime == nil { startTime = time; peak = delta }
                endTime = time
                peak = Swift.max(peak, delta)
            } else if let start = startTime {
                intervals.append(StormInterval(start: start, end: endTime,
                                               category: StormCategory(deltaNT: peak), peakDelta: peak))
                startTime = nil
                peak = 0
            }
        }

        if let start = startTime {
            intervals.append(StormInterval(start: start, end: endTime,
                                           category: StormCategory(deltaNT: peak), peakDelta: peak))
        }
        return intervals
    }
}
