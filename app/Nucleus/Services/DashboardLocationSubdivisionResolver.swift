import CoreLocation
import Foundation

struct DashboardLocationContext: Equatable {
    var countryCode: String
    var subdivisionCode: String?
    var localityName: String?
    var subdivisionName: String?

    var dashboardLocationLabel: String? {
        if let localityName, !localityName.isEmpty {
            return localityName
        }
        if let subdivisionName, !subdivisionName.isEmpty {
            return subdivisionName
        }
        return Locale.current.localizedString(forRegionCode: countryCode)
    }
}

enum DashboardLocationSubdivisionResolver {
    static func context(from placemark: CLPlacemark) -> DashboardLocationContext? {
        guard let countryCode = placemark.isoCountryCode?.uppercased(), !countryCode.isEmpty else {
            return nil
        }

        let subdivisionCode = subdivisionCode(
            countryCode: countryCode,
            administrativeArea: placemark.administrativeArea
        )
        let subdivisionName = subdivisionCode.flatMap { displayName(for: $0) }
            ?? placemark.administrativeArea

        return DashboardLocationContext(
            countryCode: countryCode,
            subdivisionCode: subdivisionCode,
            localityName: placemark.locality,
            subdivisionName: subdivisionName
        )
    }

    static func subdivisionCode(countryCode: String, administrativeArea: String?) -> String? {
        guard let administrativeArea = administrativeArea?.trimmingCharacters(in: .whitespacesAndNewlines),
              !administrativeArea.isEmpty else {
            return nil
        }

        let country = countryCode.uppercased()
        let upper = administrativeArea.uppercased()

        if upper.contains("-"), upper.hasPrefix("\(country)-") {
            return upper
        }

        if administrativeArea.count <= 3, administrativeArea.allSatisfy({ $0.isLetter }) {
            return "\(country)-\(upper)"
        }

        if let mapped = subdivisionNameLookup[country]?[administrativeArea]
            ?? subdivisionNameLookup[country]?[administrativeArea.lowercased()] {
            return mapped
        }

        return nil
    }

    static func displayName(for subdivisionCode: String) -> String {
        let parts = subdivisionCode.split(separator: "-", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return subdivisionCode }
        let country = parts[0]
        let suffix = parts[1]
        return subdivisionDisplayLookup[country]?[suffix] ?? suffix
    }

    static func displayNames(for subdivisionCodes: [String]) -> [String] {
        Array(Set(subdivisionCodes.map { displayName(for: $0) })).sorted()
    }

    private static let subdivisionNameLookup: [String: [String: String]] = [
        "AU": [
            "Australian Capital Territory": "AU-ACT",
            "New South Wales": "AU-NSW",
            "Northern Territory": "AU-NT",
            "Queensland": "AU-QLD",
            "South Australia": "AU-SA",
            "Tasmania": "AU-TAS",
            "Victoria": "AU-VIC",
            "Western Australia": "AU-WA",
        ],
        "US": [
            "Alabama": "US-AL", "Alaska": "US-AK", "Arizona": "US-AZ", "Arkansas": "US-AR",
            "California": "US-CA", "Colorado": "US-CO", "Connecticut": "US-CT", "Delaware": "US-DE",
            "District of Columbia": "US-DC", "Florida": "US-FL", "Georgia": "US-GA", "Hawaii": "US-HI",
            "Idaho": "US-ID", "Illinois": "US-IL", "Indiana": "US-IN", "Iowa": "US-IA",
            "Kansas": "US-KS", "Kentucky": "US-KY", "Louisiana": "US-LA", "Maine": "US-ME",
            "Maryland": "US-MD", "Massachusetts": "US-MA", "Michigan": "US-MI", "Minnesota": "US-MN",
            "Mississippi": "US-MS", "Missouri": "US-MO", "Montana": "US-MT", "Nebraska": "US-NE",
            "Nevada": "US-NV", "New Hampshire": "US-NH", "New Jersey": "US-NJ", "New Mexico": "US-NM",
            "New York": "US-NY", "North Carolina": "US-NC", "North Dakota": "US-ND", "Ohio": "US-OH",
            "Oklahoma": "US-OK", "Oregon": "US-OR", "Pennsylvania": "US-PA", "Rhode Island": "US-RI",
            "South Carolina": "US-SC", "South Dakota": "US-SD", "Tennessee": "US-TN", "Texas": "US-TX",
            "Utah": "US-UT", "Vermont": "US-VT", "Virginia": "US-VA", "Washington": "US-WA",
            "West Virginia": "US-WV", "Wisconsin": "US-WI", "Wyoming": "US-WY",
        ],
        "CA": [
            "Alberta": "CA-AB", "British Columbia": "CA-BC", "Manitoba": "CA-MB",
            "New Brunswick": "CA-NB", "Newfoundland and Labrador": "CA-NL", "Nova Scotia": "CA-NS",
            "Northwest Territories": "CA-NT", "Nunavut": "CA-NU", "Ontario": "CA-ON",
            "Prince Edward Island": "CA-PE", "Quebec": "CA-QC", "Saskatchewan": "CA-SK",
            "Yukon": "CA-YT",
        ],
    ]

    private static let subdivisionDisplayLookup: [String: [String: String]] = [
        "AU": [
            "ACT": "Australian Capital Territory",
            "NSW": "New South Wales",
            "NT": "Northern Territory",
            "QLD": "Queensland",
            "SA": "South Australia",
            "TAS": "Tasmania",
            "VIC": "Victoria",
            "WA": "Western Australia",
        ],
        "US": [
            "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas",
            "CA": "California", "CO": "Colorado", "CT": "Connecticut", "DE": "Delaware",
            "DC": "District of Columbia", "FL": "Florida", "GA": "Georgia", "HI": "Hawaii",
            "ID": "Idaho", "IL": "Illinois", "IN": "Indiana", "IA": "Iowa",
            "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine",
            "MD": "Maryland", "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota",
            "MS": "Mississippi", "MO": "Missouri", "MT": "Montana", "NE": "Nebraska",
            "NV": "Nevada", "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico",
            "NY": "New York", "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio",
            "OK": "Oklahoma", "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island",
            "SC": "South Carolina", "SD": "South Dakota", "TN": "Tennessee", "TX": "Texas",
            "UT": "Utah", "VT": "Vermont", "VA": "Virginia", "WA": "Washington",
            "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming",
        ],
        "CA": [
            "AB": "Alberta", "BC": "British Columbia", "MB": "Manitoba", "NB": "New Brunswick",
            "NL": "Newfoundland and Labrador", "NS": "Nova Scotia", "NT": "Northwest Territories",
            "NU": "Nunavut", "ON": "Ontario", "PE": "Prince Edward Island", "QC": "Quebec",
            "SK": "Saskatchewan", "YT": "Yukon",
        ],
    ]
}
