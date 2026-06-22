// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Seed directory of INTERMAGNET observatories.
///
/// This is a starting list for the picker; the authoritative station name and coordinates
/// arrive in each IAGA-2002 header and take precedence once data is fetched. Coordinates
/// here are approximate (geodetic latitude °N, longitude °E in [-180, 180]).
public enum Observatories {
    public static let `default` = GeomagObservatory(
        code: "FRD", name: "Fredericksburg", country: "United States",
        latitude: 38.20, longitude: -77.37)

    public static let all: [GeomagObservatory] = [
        // North America (USGS / NRCan)
        .init(code: "FRD", name: "Fredericksburg", country: "United States", latitude: 38.20, longitude: -77.37),
        .init(code: "BOU", name: "Boulder", country: "United States", latitude: 40.14, longitude: -105.24),
        .init(code: "BSL", name: "Stennis (Bay St. Louis)", country: "United States", latitude: 30.35, longitude: -89.64),
        .init(code: "TUC", name: "Tucson", country: "United States", latitude: 32.17, longitude: -110.73),
        .init(code: "NEW", name: "Newport", country: "United States", latitude: 48.27, longitude: -117.12),
        .init(code: "SJG", name: "San Juan", country: "Puerto Rico", latitude: 18.11, longitude: -66.15),
        .init(code: "HON", name: "Honolulu", country: "United States", latitude: 21.32, longitude: -158.00),
        .init(code: "SIT", name: "Sitka", country: "United States", latitude: 57.06, longitude: -135.33),
        .init(code: "CMO", name: "College (Fairbanks)", country: "United States", latitude: 64.87, longitude: -147.86),
        .init(code: "DED", name: "Deadhorse", country: "United States", latitude: 70.36, longitude: -148.79),
        .init(code: "GUA", name: "Guam", country: "United States", latitude: 13.59, longitude: 144.87),
        .init(code: "VIC", name: "Victoria", country: "Canada", latitude: 48.52, longitude: -123.42),
        .init(code: "OTT", name: "Ottawa", country: "Canada", latitude: 45.40, longitude: -75.55),
        .init(code: "MEA", name: "Meanook", country: "Canada", latitude: 54.62, longitude: -113.35),
        .init(code: "STJ", name: "St. John's", country: "Canada", latitude: 47.60, longitude: -52.68),
        .init(code: "YKC", name: "Yellowknife", country: "Canada", latitude: 62.48, longitude: -114.48),
        .init(code: "IQA", name: "Iqaluit", country: "Canada", latitude: 63.75, longitude: -68.52),
        .init(code: "RES", name: "Resolute Bay", country: "Canada", latitude: 74.69, longitude: -94.90),

        // Europe
        .init(code: "ESK", name: "Eskdalemuir", country: "United Kingdom", latitude: 55.31, longitude: -3.21),
        .init(code: "HAD", name: "Hartland", country: "United Kingdom", latitude: 50.99, longitude: -4.48),
        .init(code: "LER", name: "Lerwick", country: "United Kingdom", latitude: 60.13, longitude: -1.18),
        .init(code: "CLF", name: "Chambon-la-Forêt", country: "France", latitude: 48.02, longitude: 2.26),
        .init(code: "NGK", name: "Niemegk", country: "Germany", latitude: 52.07, longitude: 12.68),
        .init(code: "WNG", name: "Wingst", country: "Germany", latitude: 53.74, longitude: 9.07),
        .init(code: "FUR", name: "Fürstenfeldbruck", country: "Germany", latitude: 48.16, longitude: 11.28),
        .init(code: "WIC", name: "Conrad (Wien-Kobenzl)", country: "Austria", latitude: 47.93, longitude: 15.87),
        .init(code: "EBR", name: "Ebro", country: "Spain", latitude: 40.96, longitude: 0.33),
        .init(code: "BEL", name: "Belsk", country: "Poland", latitude: 51.84, longitude: 20.79),
        .init(code: "BFE", name: "Brorfelde", country: "Denmark", latitude: 55.63, longitude: 11.67),
        .init(code: "UPS", name: "Uppsala", country: "Sweden", latitude: 59.90, longitude: 17.35),
        .init(code: "ABK", name: "Abisko", country: "Sweden", latitude: 68.36, longitude: 18.82),
        .init(code: "DOB", name: "Dombås", country: "Norway", latitude: 62.07, longitude: 9.11),
        .init(code: "SOD", name: "Sodankylä", country: "Finland", latitude: 67.37, longitude: 26.63),
        .init(code: "NUR", name: "Nurmijärvi", country: "Finland", latitude: 60.51, longitude: 24.66),

        // Greenland & high Arctic
        .init(code: "THL", name: "Qaanaaq (Thule)", country: "Greenland", latitude: 77.47, longitude: -69.23),
        .init(code: "GDH", name: "Qeqertarsuaq (Godhavn)", country: "Greenland", latitude: 69.25, longitude: -53.53),
        .init(code: "NAQ", name: "Narsarsuaq", country: "Greenland", latitude: 61.16, longitude: -45.44),

        // Asia
        .init(code: "KAK", name: "Kakioka", country: "Japan", latitude: 36.23, longitude: 140.19),
        .init(code: "MMB", name: "Memambetsu", country: "Japan", latitude: 43.91, longitude: 144.19),
        .init(code: "KNY", name: "Kanoya", country: "Japan", latitude: 31.42, longitude: 130.88),
        .init(code: "BMT", name: "Beijing Ming Tombs", country: "China", latitude: 40.30, longitude: 116.20),
        .init(code: "ABG", name: "Alibag", country: "India", latitude: 18.64, longitude: 72.87),
        .init(code: "HYB", name: "Hyderabad", country: "India", latitude: 17.42, longitude: 78.55),
        .init(code: "IRT", name: "Irkutsk", country: "Russia", latitude: 52.17, longitude: 104.45),
        .init(code: "NVS", name: "Novosibirsk", country: "Russia", latitude: 54.85, longitude: 83.23),

        // Africa & Middle East
        .init(code: "TAM", name: "Tamanrasset", country: "Algeria", latitude: 22.79, longitude: 5.53),
        .init(code: "AAE", name: "Addis Ababa", country: "Ethiopia", latitude: 9.04, longitude: 38.77),
        .init(code: "HER", name: "Hermanus", country: "South Africa", latitude: -34.43, longitude: 19.23),
        .init(code: "HBK", name: "Hartebeesthoek", country: "South Africa", latitude: -25.88, longitude: 27.71),

        // Oceania & Pacific
        .init(code: "CNB", name: "Canberra", country: "Australia", latitude: -35.32, longitude: 149.36),
        .init(code: "GNG", name: "Gingin", country: "Australia", latitude: -31.36, longitude: 115.72),
        .init(code: "ASP", name: "Alice Springs", country: "Australia", latitude: -23.76, longitude: 133.88),
        .init(code: "EYR", name: "Eyrewell", country: "New Zealand", latitude: -43.42, longitude: 172.35),
        .init(code: "API", name: "Apia", country: "Samoa", latitude: -13.81, longitude: -171.78),

        // South America & Antarctica
        .init(code: "VSS", name: "Vassouras", country: "Brazil", latitude: -22.40, longitude: -43.65),
        .init(code: "PIL", name: "Pilar", country: "Argentina", latitude: -31.67, longitude: -63.88),
        .init(code: "TRW", name: "Trelew", country: "Argentina", latitude: -43.27, longitude: -65.32),
        .init(code: "CZT", name: "Port-aux-Français (Crozet/Kerguelen)", country: "France (TAAF)", latitude: -49.35, longitude: 70.26),
        .init(code: "MAW", name: "Mawson", country: "Antarctica", latitude: -67.60, longitude: 62.88),
    ]

    private static let byCode: [String: GeomagObservatory] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.code, $0) })

    public static func observatory(code: String) -> GeomagObservatory? {
        byCode[code.uppercased()]
    }

    /// Case-insensitive search over IAGA code, name, and country.
    public static func search(_ query: String) -> [GeomagObservatory] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return all }
        let needle = trimmed.lowercased()
        return all.filter {
            $0.code.lowercased().contains(needle)
                || $0.name.lowercased().contains(needle)
                || $0.country.lowercased().contains(needle)
        }
    }
}
