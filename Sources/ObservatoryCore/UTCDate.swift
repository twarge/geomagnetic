// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Fast, dependency-free UTC date arithmetic.
///
/// Geomagnetic data is organized strictly in UTC days, and the IAGA-2002 parser turns
/// every data line into an epoch timestamp. Both paths run in hot loops over thousands
/// of samples, so this avoids `DateFormatter`/`Calendar` per row in favor of the
/// days-from-civil algorithm.
public enum UTCDate {
    public static let secondsPerDay: Double = 86_400

    /// Days since the Unix epoch (1970-01-01) for a Gregorian Y/M/D, after Howard
    /// Hinnant's `days_from_civil`. Valid for the full proleptic Gregorian calendar.
    public static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400                                  // [0, 399]
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1   // [0, 365]
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy         // [0, 146096]
        return era * 146_097 + doe - 719_468
    }

    /// Inverse of `daysFromCivil`: civil Y/M/D from days since the Unix epoch.
    public static func civilFromDays(_ z0: Int) -> (year: Int, month: Int, day: Int) {
        let z = z0 + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097                              // [0, 146096]
        let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365  // [0, 399]
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)        // [0, 365]
        let mp = (5 * doy + 2) / 153                             // [0, 11]
        let day = doy - (153 * mp + 2) / 5 + 1                   // [1, 31]
        let month = mp < 10 ? mp + 3 : mp - 9                    // [1, 12]
        return (mp < 10 ? y : y + 1, month, day)
    }

    /// Epoch seconds for a UTC wall-clock instant.
    public static func epoch(year: Int, month: Int, day: Int,
                             hour: Int = 0, minute: Int = 0, second: Double = 0) -> Double {
        Double(daysFromCivil(year: year, month: month, day: day)) * secondsPerDay
            + Double(hour) * 3_600 + Double(minute) * 60 + second
    }

    /// Epoch seconds at 00:00:00 UTC of the day containing `epoch`.
    public static func startOfDay(_ epoch: Double) -> Double {
        (epoch / secondsPerDay).rounded(.down) * secondsPerDay
    }

    /// Epoch seconds at 00:00:00 UTC of the day containing `date`.
    public static func startOfDay(_ date: Date) -> Double {
        startOfDay(date.timeIntervalSince1970)
    }

    /// `yyyy-MM-dd` for a UTC day-start epoch — used both for GIN requests and as the
    /// cache file name.
    public static func dayString(_ dayStartEpoch: Double) -> String {
        let (year, month, day) = civilFromDays(Int((dayStartEpoch / secondsPerDay).rounded()))
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// All UTC day-start epochs in `[from, to]`, inclusive of both endpoints' days.
    public static func dayStarts(from: Date, to: Date) -> [Double] {
        let first = startOfDay(from)
        let last = startOfDay(to)
        guard last >= first else { return [first] }
        return stride(from: first, through: last, by: secondsPerDay).map { $0 }
    }
}
