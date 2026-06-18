import Foundation

struct DashboardPublicHolidayCountryOption: Identifiable, Equatable, Codable {
    var countryCode: String
    var name: String

    var id: String { countryCode }

    init(countryCode: String, name: String) {
        self.countryCode = countryCode.uppercased()
        self.name = name
    }
}

enum DashboardPublicHolidayCountryCatalog {
    private struct RemoteCountry: Decodable {
        let countryCode: String
        let name: String
    }

    private static let cacheKey = "nucleus.dashboard.publicHolidayCountryCatalog"
    private static let cacheTTL: TimeInterval = 7 * 24 * 60 * 60

    static func localizedCountryName(for countryCode: String) -> String {
        let normalized = countryCode.uppercased()
        return Locale.current.localizedString(forRegionCode: normalized) ?? normalized
    }

    static func loadCachedCountries() -> [DashboardPublicHolidayCountryOption] {
        guard
            let data = UserDefaults.standard.data(forKey: cacheKey),
            let payload = try? JSONDecoder().decode(CachedPayload.self, from: data),
            Date().timeIntervalSince(payload.savedAt) < cacheTTL
        else {
            return fallbackCountries()
        }
        return payload.countries
    }

    static func fetchCountries() async -> [DashboardPublicHolidayCountryOption] {
        if let remote = await fetchRemoteCountries(), !remote.isEmpty {
            cacheCountries(remote)
            return remote
        }
        return loadCachedCountries()
    }

    private static func fetchRemoteCountries() async -> [DashboardPublicHolidayCountryOption]? {
        guard let url = URL(string: "https://date.nager.at/api/v3/AvailableCountries") else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let records = try JSONDecoder().decode([RemoteCountry].self, from: data)
            return records
                .map {
                    DashboardPublicHolidayCountryOption(
                        countryCode: $0.countryCode,
                        name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
                .filter { !$0.countryCode.isEmpty && !$0.name.isEmpty }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            return nil
        }
    }

    private static func cacheCountries(_ countries: [DashboardPublicHolidayCountryOption]) {
        let payload = CachedPayload(savedAt: Date(), countries: countries)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    private static func fallbackCountries() -> [DashboardPublicHolidayCountryOption] {
        let codes = [
            "AU", "US", "GB", "CA", "NZ", "SG", "MY", "ID", "IN", "JP",
            "DE", "FR", "NL", "IE", "PH", "TH", "VN", "HK", "KR", "CN",
        ]
        return codes.map { code in
            DashboardPublicHolidayCountryOption(
                countryCode: code,
                name: localizedCountryName(for: code)
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private struct CachedPayload: Codable {
        let savedAt: Date
        let countries: [DashboardPublicHolidayCountryOption]
    }
}
