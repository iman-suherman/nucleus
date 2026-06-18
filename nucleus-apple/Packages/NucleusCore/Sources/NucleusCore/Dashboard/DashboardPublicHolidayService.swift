import Foundation

public struct DashboardNextPublicHoliday: Equatable, Sendable {
    public var name: String
    public var date: Date
    public var daysUntil: Int
    public var countryCode: String
    public var isNationwide: Bool
    public var applicableRegions: [String]

    public init(
        name: String,
        date: Date,
        daysUntil: Int,
        countryCode: String,
        isNationwide: Bool = true,
        applicableRegions: [String] = []
    ) {
        self.name = name
        self.date = date
        self.daysUntil = daysUntil
        self.countryCode = countryCode
        self.isNationwide = isNationwide
        self.applicableRegions = applicableRegions
    }

    public var relativeDescription: String {
        switch daysUntil {
        case 0: return "Today"
        case 1: return "Tomorrow"
        default: return "In \(daysUntil) days"
        }
    }

    public var applicabilityLabel: String? {
        guard !isNationwide, !applicableRegions.isEmpty else { return nil }
        if applicableRegions.count == 1 {
            return "Applies in \(applicableRegions[0])"
        }
        return "Applies in: \(applicableRegions.joined(separator: ", "))"
    }

    public var scopeLabel: String {
        isNationwide ? "Nationwide" : "State & regional"
    }
}

public struct DashboardPublicHolidayCountryGroup: Identifiable, Equatable, Sendable {
    public var countryCode: String
    public var countryName: String
    public var locationLabel: String?
    public var holidays: [DashboardNextPublicHoliday]

    public var id: String { countryCode }

    public init(
        countryCode: String,
        countryName: String,
        locationLabel: String? = nil,
        holidays: [DashboardNextPublicHoliday]
    ) {
        self.countryCode = countryCode.uppercased()
        self.countryName = countryName
        self.locationLabel = locationLabel
        self.holidays = holidays
    }
}

public struct DashboardPublicHolidayRefreshTarget: Equatable, Sendable {
    public var countryCode: String
    public var subdivisionCode: String?
    public var locationLabel: String?
    public var countryName: String

    public init(
        countryCode: String,
        subdivisionCode: String? = nil,
        locationLabel: String? = nil,
        countryName: String
    ) {
        self.countryCode = countryCode.uppercased()
        self.subdivisionCode = subdivisionCode?.uppercased()
        self.locationLabel = locationLabel
        self.countryName = countryName
    }
}

public enum DashboardPublicHolidayClient {
    private struct HolidayRecord: Decodable {
        let date: String
        let localName: String
        let name: String
        let global: Bool
        let counties: [String]?
    }

    public static func fetchNextPublicHolidays(
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

    public static func isPublicHoliday(on date: Date, in holidays: [DashboardNextPublicHoliday]) -> Bool {
        let calendar = Calendar.current
        let target = calendar.startOfDay(for: date)
        return holidays.contains { calendar.isDate($0.date, inSameDayAs: target) }
    }

    public static func displayHolidays(from holidays: [DashboardNextPublicHoliday]) -> [DashboardNextPublicHoliday] {
        guard !holidays.isEmpty else { return [] }

        let nationwide = holidays.first(where: \.isNationwide)
        let regional = holidays.first(where: { !$0.isNationwide })

        var result: [DashboardNextPublicHoliday] = []
        if let nationwide {
            result.append(nationwide)
        }
        if let regional {
            let duplicate = nationwide.map { sameDisplayHoliday($0, regional) } ?? false
            if !duplicate {
                result.append(regional)
            }
        }
        if result.isEmpty, let first = holidays.first {
            result = [first]
        }
        return result.sorted { $0.date < $1.date }
    }

    private static func sameDisplayHoliday(
        _ lhs: DashboardNextPublicHoliday,
        _ rhs: DashboardNextPublicHoliday
    ) -> Bool {
        lhs.name.caseInsensitiveCompare(rhs.name) == .orderedSame
            && Calendar.current.isDate(lhs.date, inSameDayAs: rhs.date)
    }
}

@MainActor
public final class DashboardPublicHolidayService: ObservableObject {
    public static let shared = DashboardPublicHolidayService()

    @Published public private(set) var nextHoliday: DashboardNextPublicHoliday?
    @Published public private(set) var displayHolidays: [DashboardNextPublicHoliday] = []
    @Published public private(set) var countryGroups: [DashboardPublicHolidayCountryGroup] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var statusMessage: String?
    @Published public private(set) var locationLabel: String?

    private var cachedHolidays: [DashboardNextPublicHoliday] = []
    private var cachedTargetsKey: String?
    private var lastFetchAt: Date?
    private var fetchTask: Task<Void, Never>?

    private static let refreshInterval: TimeInterval = 24 * 60 * 60
    public static let maxSelectedCountries = 2

    private init() {}

    public var isTodayPublicHoliday: Bool {
        DashboardPublicHolidayClient.isPublicHoliday(on: Date(), in: cachedHolidays)
    }

    public static func resolveRefreshTargets(
        selectedCountryCodes: [String],
        locationCountryCode: String?,
        locationSubdivisionCode: String? = nil,
        locationLabel: String? = nil
    ) -> [DashboardPublicHolidayRefreshTarget] {
        let normalizedSelected = normalizedCountryCodes(selectedCountryCodes)
        let locationCode = locationCountryCode?.uppercased()

        let effectiveCodes: [String]
        if normalizedSelected.isEmpty {
            guard let locationCode, !locationCode.isEmpty else { return [] }
            effectiveCodes = [locationCode]
        } else {
            effectiveCodes = normalizedSelected
        }

        return effectiveCodes.map { code in
            let usesLocation = code == locationCode
            return DashboardPublicHolidayRefreshTarget(
                countryCode: code,
                subdivisionCode: usesLocation ? locationSubdivisionCode : nil,
                locationLabel: usesLocation ? locationLabel : nil,
                countryName: DashboardPublicHolidayCountryCatalog.localizedCountryName(for: code)
            )
        }
    }

    public static func normalizedCountryCodes(_ codes: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in codes {
            let code = raw.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard code.count == 2, !seen.contains(code) else { continue }
            seen.insert(code)
            result.append(code)
            if result.count >= maxSelectedCountries { break }
        }
        return result
    }

    public func refresh(
        selectedCountryCodes: [String] = [],
        locationCountryCode: String?,
        locationSubdivisionCode: String? = nil,
        locationLabel: String? = nil,
        force: Bool = false
    ) {
        let targets = Self.resolveRefreshTargets(
            selectedCountryCodes: selectedCountryCodes,
            locationCountryCode: locationCountryCode,
            locationSubdivisionCode: locationSubdivisionCode,
            locationLabel: locationLabel
        )
        self.locationLabel = targets.count == 1 ? targets[0].locationLabel : nil

        guard !targets.isEmpty else {
            clear()
            statusMessage = "Choose up to two countries in Settings, or allow location access."
            return
        }

        let targetsKey = targets
            .map { "\($0.countryCode)|\($0.subdivisionCode ?? "")" }
            .joined(separator: ";")

        if !force,
           targetsKey == cachedTargetsKey,
           let lastFetchAt,
           Date().timeIntervalSince(lastFetchAt) < Self.refreshInterval,
           !countryGroups.isEmpty {
            return
        }

        fetchTask?.cancel()
        fetchTask = Task { @MainActor in
            await loadHolidays(targets: targets, targetsKey: targetsKey)
        }
    }

    public func refresh(
        countryCode: String?,
        subdivisionCode: String? = nil,
        locationLabel: String? = nil,
        force: Bool = false
    ) {
        refresh(
            selectedCountryCodes: [],
            locationCountryCode: countryCode,
            locationSubdivisionCode: subdivisionCode,
            locationLabel: locationLabel,
            force: force
        )
    }

    public func clear() {
        fetchTask?.cancel()
        fetchTask = nil
        nextHoliday = nil
        displayHolidays = []
        countryGroups = []
        cachedHolidays = []
        cachedTargetsKey = nil
        locationLabel = nil
        statusMessage = nil
        isLoading = false
    }

    private func loadHolidays(targets: [DashboardPublicHolidayRefreshTarget], targetsKey: String) async {
        isLoading = true
        statusMessage = nil
        defer { isLoading = false }

        var groups: [DashboardPublicHolidayCountryGroup] = []
        var allHolidays: [DashboardNextPublicHoliday] = []
        var hadError = false

        await withTaskGroup(of: (DashboardPublicHolidayRefreshTarget, Result<[DashboardNextPublicHoliday], Error>).self) { taskGroup in
            for target in targets {
                taskGroup.addTask {
                    do {
                        let holidays = try await DashboardPublicHolidayClient.fetchNextPublicHolidays(
                            countryCode: target.countryCode,
                            subdivisionCode: target.subdivisionCode
                        )
                        return (target, .success(holidays))
                    } catch {
                        return (target, .failure(error))
                    }
                }
            }

            for await (target, result) in taskGroup {
                guard !Task.isCancelled else { return }
                switch result {
                case .success(let holidays):
                    let display = DashboardPublicHolidayClient.displayHolidays(from: holidays)
                    groups.append(
                        DashboardPublicHolidayCountryGroup(
                            countryCode: target.countryCode,
                            countryName: target.countryName,
                            locationLabel: target.locationLabel,
                            holidays: display
                        )
                    )
                    allHolidays.append(contentsOf: holidays)
                case .failure:
                    hadError = true
                }
            }
        }

        guard !Task.isCancelled else { return }

        groups.sort { $0.countryName.localizedCaseInsensitiveCompare($1.countryName) == .orderedAscending }
        countryGroups = groups
        cachedHolidays = allHolidays
        cachedTargetsKey = targetsKey
        lastFetchAt = Date()
        displayHolidays = groups.flatMap(\.holidays)
        nextHoliday = displayHolidays.min(by: { $0.date < $1.date })

        if groups.isEmpty {
            if hadError {
                statusMessage = "Couldn't load public holidays right now."
            } else if targets.contains(where: { $0.subdivisionCode == nil }) {
                statusMessage = "Allow location access to show state public holidays."
            } else {
                statusMessage = "No upcoming public holidays found."
            }
        } else {
            statusMessage = nil
        }
    }
}
