// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0
//
// App Intents vocabulary shared by the app, the widgets, and Siri:
//   • StationEntity / FieldComponent — the "nouns" (observatory, element)
//   • CurrentFieldIntent — "What's the total magnetic field at Fredericksburg?"
//   • ObservatoryWidgetConfigIntent — the widget's Edit-Widget configuration
//     (right-click a widget → Edit to choose the station and component).

import AppIntents
import Foundation

// MARK: - Station (AppEntity)

public struct StationEntity: AppEntity, Identifiable, Sendable {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Observatory")
    public static let defaultQuery = StationQuery()

    public var id: String                 // IAGA code
    public var name: String
    public var country: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(id) · \(country)")
    }

    public init(observatory: GeomagObservatory) {
        id = observatory.code
        name = observatory.name
        country = observatory.country
    }
}

public struct StationQuery: EntityQuery, EntityStringQuery, Sendable {
    public init() {}

    public func entities(for identifiers: [String]) async throws -> [StationEntity] {
        identifiers.compactMap { Observatories.observatory(code: $0).map(StationEntity.init) }
    }

    /// Free-text lookup so Siri can resolve "Fredericksburg" or "FRD".
    public func entities(matching string: String) async throws -> [StationEntity] {
        Observatories.search(string).map(StationEntity.init)
    }

    public func suggestedEntities() async throws -> [StationEntity] {
        // Favorites first (the app's current station is always a favorite candidate).
        let favorites = ObservatorySettings.favorites
        let ordered = Observatories.all.sorted {
            (favorites.contains($0.code) ? 0 : 1, $0.name) < (favorites.contains($1.code) ? 0 : 1, $1.name)
        }
        return ordered.map(StationEntity.init)
    }

    public func defaultResult() async -> StationEntity? {
        Observatories.observatory(code: ObservatorySettings.observatoryCode).map(StationEntity.init)
    }
}

// MARK: - Field component (AppEnum)

public enum FieldComponent: String, AppEnum, Sendable {
    case total = "F"
    case north = "X"
    case east = "Y"
    case vertical = "Z"
    case horizontal = "H"
    case declination = "D"

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Field Component")
    public static let caseDisplayRepresentations: [FieldComponent: DisplayRepresentation] = [
        .total: "Total field (F)",
        .north: "Northward (X)",
        .east: "Eastward (Y)",
        .vertical: "Vertical (Z)",
        .horizontal: "Horizontal (H)",
        .declination: "Declination (D)",
    ]
}

// MARK: - Time range (AppEnum)

extension ObservatoryTimeRange: AppEnum {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Time Range")
    public static let caseDisplayRepresentations: [ObservatoryTimeRange: DisplayRepresentation] = [
        .threeHours: "3 Hours",
        .sixHours: "6 Hours",
        .day: "1 Day",
        .threeDays: "3 Days",
        .week: "1 Week",
        .month: "1 Month",
    ]
}

// MARK: - "What's the field?" (Siri / Shortcuts)

public struct CurrentFieldIntent: AppIntent {
    public static let title: LocalizedStringResource = "Get Magnetic Field"
    public static let description = IntentDescription(
        "Reads the latest geomagnetic field measurement at an INTERMAGNET observatory.")

    @Parameter(title: "Observatory")
    public var station: StationEntity?

    @Parameter(title: "Component", default: .total)
    public var component: FieldComponent

    public static var parameterSummary: some ParameterSummary {
        Summary("Get the \(\.$component) at \(\.$station)")
    }

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Double> {
        let code = station?.id ?? ObservatorySettings.observatoryCode
        let observatory = Observatories.observatory(code: code) ?? Observatories.default
        let window = ObservatoryTimeRange.threeHours.dateRange()

        let repo = GeomagRepository.shared
        var result = try? await repo.series(code: observatory.code,
                                            from: window.lowerBound, to: window.upperBound,
                                            maxPoints: 64)
        if result == nil || result?.isEmpty == true {
            result = await repo.cachedSeries(code: observatory.code,
                                             from: window.lowerBound, to: window.upperBound,
                                             maxPoints: 64)
        }

        let series = result?.series.first { $0.element.code == component.rawValue }
            ?? result?.series.first
        guard let series, let latest = series.latest else {
            throw NSError(domain: "Geomagnetic", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No recent data for \(observatory.name)."])
        }

        let componentName = FieldComponent(rawValue: series.element.code)
            .map { String(localized: Self.spokenName(for: $0)) } ?? series.element.code
        let value = latest.value
        let unit = series.element.unit == "nT" ? "nanoteslas" : series.element.unit
        let when = Date(timeIntervalSince1970: latest.time)
            .formatted(date: .omitted, time: .shortened)
        let dialog = IntentDialog(
            "The \(componentName) at \(observatory.name) is \(value.formatted(.number.precision(.fractionLength(1)))) \(unit), as of \(when).")
        return .result(value: value, dialog: dialog)
    }

    private static func spokenName(for component: FieldComponent) -> String.LocalizationValue {
        switch component {
        case .total: return "total magnetic field"
        case .north: return "northward field component"
        case .east: return "eastward field component"
        case .vertical: return "vertical field component"
        case .horizontal: return "horizontal field intensity"
        case .declination: return "declination"
        }
    }
}

// MARK: - Widget configuration (Edit Widget)

public struct ObservatoryWidgetConfigIntent: WidgetConfigurationIntent {
    public static let title: LocalizedStringResource = "Observatory Widget"
    public static let description = IntentDescription(
        "Choose which observatory and field component the widget shows.")

    /// nil ⇒ follow the station selected in the app.
    @Parameter(title: "Observatory")
    public var station: StationEntity?

    /// nil ⇒ the app's usual preference (F first).
    @Parameter(title: "Component")
    public var component: FieldComponent?

    /// nil ⇒ follow the time range selected in the app.
    @Parameter(title: "Time Range")
    public var range: ObservatoryTimeRange?

    public init() {}
}
