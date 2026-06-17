import Foundation

struct DashboardNextPublicHoliday: Equatable {
    var name: String
    var date: Date
    var daysUntil: Int
    var countryCode: String
    var isNationwide: Bool
    var applicableRegions: [String]

    var relativeDescription: String {
        switch daysUntil {
        case 0: return "Today"
        case 1: return "Tomorrow"
        default: return "In \(daysUntil) days"
        }
    }

    var applicabilityLabel: String? {
        guard !isNationwide, !applicableRegions.isEmpty else { return nil }
        if applicableRegions.count == 1 {
            return "Applies in \(applicableRegions[0])"
        }
        return "Applies in: \(applicableRegions.joined(separator: ", "))"
    }
}

enum DashboardPublicHolidayClient {
    private struct HolidayRecord: Decodable {
        let date: String
        let localName: String
        let name: String
        let global: Bool
        let counties: [String]?
    }

    static func fetchNextPublicHolidays(
        countryCode: String,
        subdivisionCode: String?
    ) async throws -> [DashboardNextPublicHoliday] {
        let normalized = countryCode.uppercased()
        guard normalized.count == 2 else {
            throw URLError(.badURL)
        }

        let url = URL(string: "https://date.nager.at/api/v3/NextPublicHolidays/\(normalized)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let records = try JSONDecoder().decode([HolidayRecord].self, from: data)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let userSubdivision = subdivisionCode?.uppercased()

        return records.compactMap { record in
            guard appliesToUser(record: record, subdivisionCode: userSubdivision) else { return nil }

            guard let date = formatter.date(from: record.date) else { return nil }
            let day = calendar.startOfDay(for: date)
            let daysUntil = calendar.dateComponents([.day], from: today, to: day).day ?? 0
            guard daysUntil >= 0 else { return nil }
            let label = record.localName.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = record.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = label.isEmpty ? fallback : label
            guard !name.isEmpty else { return nil }

            let regions = record.global
                ? []
                : DashboardLocationSubdivisionResolver.displayNames(for: record.counties ?? [])

            return DashboardNextPublicHoliday(
                name: name,
                date: day,
                daysUntil: daysUntil,
                countryCode: normalized,
                isNationwide: record.global,
                applicableRegions: regions
            )
        }
    }

    private static func appliesToUser(record: HolidayRecord, subdivisionCode: String?) -> Bool {
        if record.global { return true }
        guard let counties = record.counties, !counties.isEmpty else {
            return record.global
        }
        guard let subdivisionCode else {
            return false
        }
        return counties.contains { $0.uppercased() == subdivisionCode }
    }

    static func isPublicHoliday(on date: Date, in holidays: [DashboardNextPublicHoliday]) -> Bool {
        let calendar = Calendar.current
        let target = calendar.startOfDay(for: date)
        return holidays.contains { calendar.isDate($0.date, inSameDayAs: target) }
    }
}

@MainActor
final class DashboardPublicHolidayService: ObservableObject {
    static let shared = DashboardPublicHolidayService()

    @Published private(set) var nextHoliday: DashboardNextPublicHoliday?
    @Published private(set) var isLoading = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var locationLabel: String?

    private var cachedHolidays: [DashboardNextPublicHoliday] = []
    private var cachedCountryCode: String?
    private var cachedSubdivisionCode: String?
    private var lastFetchAt: Date?
    private var fetchTask: Task<Void, Never>?

    private static let refreshInterval: TimeInterval = 24 * 60 * 60

    private init() {}

    var isTodayPublicHoliday: Bool {
        DashboardPublicHolidayClient.isPublicHoliday(on: Date(), in: cachedHolidays)
    }

    func refresh(
        countryCode: String?,
        subdivisionCode: String? = nil,
        locationLabel: String? = nil,
        force: Bool = false
    ) {
        self.locationLabel = locationLabel

        guard let countryCode, !countryCode.isEmpty else {
            nextHoliday = nil
            cachedHolidays = []
            cachedCountryCode = nil
            cachedSubdivisionCode = nil
            statusMessage = "Location is needed to show public holidays."
            return
        }

        let normalized = countryCode.uppercased()
        let normalizedSubdivision = subdivisionCode?.uppercased()
        if !force,
           normalized == cachedCountryCode,
           normalizedSubdivision == cachedSubdivisionCode,
           let lastFetchAt,
           Date().timeIntervalSince(lastFetchAt) < Self.refreshInterval,
           nextHoliday != nil {
            return
        }

        fetchTask?.cancel()
        fetchTask = Task { @MainActor in
            await loadHolidays(countryCode: normalized, subdivisionCode: normalizedSubdivision)
        }
    }

    func clear() {
        fetchTask?.cancel()
        fetchTask = nil
        nextHoliday = nil
        cachedHolidays = []
        cachedCountryCode = nil
        cachedSubdivisionCode = nil
        locationLabel = nil
        statusMessage = nil
        isLoading = false
    }

    private func loadHolidays(countryCode: String, subdivisionCode: String?) async {
        isLoading = true
        statusMessage = nil
        defer { isLoading = false }

        do {
            let holidays = try await DashboardPublicHolidayClient.fetchNextPublicHolidays(
                countryCode: countryCode,
                subdivisionCode: subdivisionCode
            )
            guard !Task.isCancelled else { return }
            cachedHolidays = holidays
            cachedCountryCode = countryCode
            cachedSubdivisionCode = subdivisionCode
            lastFetchAt = Date()
            nextHoliday = holidays.first
            if holidays.isEmpty {
                if subdivisionCode == nil {
                    statusMessage = "Allow location access to show state public holidays."
                } else {
                    statusMessage = "No upcoming public holidays found for your state."
                }
            } else {
                statusMessage = nil
            }
        } catch {
            guard !Task.isCancelled else { return }
            nextHoliday = nil
            cachedHolidays = []
            statusMessage = "Couldn't load public holidays right now."
        }
    }
}
