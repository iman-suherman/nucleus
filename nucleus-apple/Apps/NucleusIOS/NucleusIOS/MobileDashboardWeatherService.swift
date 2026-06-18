import CoreLocation
import Foundation
import NucleusCore
import OSLog
import UIKit
import WeatherKit

@MainActor
final class MobileDashboardWeatherService: NSObject, ObservableObject {
    static let shared = MobileDashboardWeatherService()

    private static let locationPromptCompletedKey = "nucleus.mobile.weather.locationPromptCompleted"
    private static let locationDeclinedKey = "nucleus.mobile.weather.locationDeclined"
    private static let weatherRefreshInterval: TimeInterval = 15 * 60

    @Published private(set) var weather: DashboardTodayWeather?
    @Published private(set) var isLoading = false
    @Published private(set) var statusMessage: String?
    @Published var showLocationPermissionPrompt = false

    private let weatherService = WeatherService.shared
    private let locationManager = CLLocationManager()
    private let logger = Logger(subsystem: NucleusAppIdentity.bundleIdentifier, category: "DashboardWeather")
    private var hasStarted = false
    private var pendingLocationRequest = false
    private var weatherFetchTask: Task<Void, Never>?
    private var isFetchingWeather = false
    private var weatherFetchGeneration = 0
    private var lastSuccessfulFetchAt: Date?

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    var locationAccessPrompt: DashboardWeatherLocationPrompt? {
        if UserDefaults.standard.bool(forKey: Self.locationDeclinedKey) {
            return DashboardWeatherLocationPrompt(
                message: "Today's weather is hidden because location access is off in Nucleus.",
                steps: Self.settingsSteps,
                buttonTitle: "Enable Weather",
                action: .reenableAfterDecline
            )
        }

        switch locationManager.authorizationStatus {
        case .denied:
            return DashboardWeatherLocationPrompt(
                message: "Nucleus needs location access to show today's forecast.",
                steps: Self.settingsSteps,
                buttonTitle: "Open Settings",
                action: .openSettings
            )
        case .restricted:
            return DashboardWeatherLocationPrompt(
                message: "Location access is restricted on this device, so today's weather can't be shown.",
                steps: Self.restrictedSteps,
                buttonTitle: "Open Settings",
                action: .openSettings
            )
        case .notDetermined:
            return DashboardWeatherLocationPrompt(
                message: "Allow location access to show today's forecast on your Dashboard.",
                steps: Self.firstRequestSteps,
                buttonTitle: "Enable Location",
                action: .requestAuthorization
            )
        case .authorizedAlways, .authorizedWhenInUse:
            return nil
        @unknown default:
            return nil
        }
    }

    func beginWeatherAccessFlow() {
        guard !hasStarted else {
            requestWeatherIfAuthorized(force: false)
            return
        }
        hasStarted = true

        if shouldOfferLocationPrompt {
            showLocationPermissionPrompt = true
            return
        }

        requestWeatherIfAuthorized()
    }

    func confirmLocationPermissionRequest() {
        UserDefaults.standard.set(true, forKey: Self.locationPromptCompletedKey)
        showLocationPermissionPrompt = false
        locationManager.requestWhenInUseAuthorization()
    }

    func declineLocationPermission() {
        UserDefaults.standard.set(true, forKey: Self.locationPromptCompletedKey)
        UserDefaults.standard.set(true, forKey: Self.locationDeclinedKey)
        showLocationPermissionPrompt = false
        weather = nil
        isLoading = false
        statusMessage = nil
    }

    func refreshIfNeeded() {
        beginWeatherAccessFlow()
    }

    func retryWeatherFetch() {
        pendingLocationRequest = false
        statusMessage = nil
        requestWeatherIfAuthorized(force: true)
    }

    func performLocationAccessAction(_ action: DashboardWeatherLocationPrompt.Action) {
        switch action {
        case .requestAuthorization:
            confirmLocationPermissionRequest()
        case .openSettings:
            openLocationSettings()
        case .reenableAfterDecline:
            UserDefaults.standard.set(false, forKey: Self.locationDeclinedKey)
            UserDefaults.standard.set(false, forKey: Self.locationPromptCompletedKey)
            hasStarted = false
            beginWeatherAccessFlow()
        }
    }

    func openLocationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var shouldOfferLocationPrompt: Bool {
        !UserDefaults.standard.bool(forKey: Self.locationPromptCompletedKey)
            && !UserDefaults.standard.bool(forKey: Self.locationDeclinedKey)
            && locationManager.authorizationStatus == .notDetermined
    }

    private var isLocationAuthorized: Bool {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }

    private func requestWeatherIfAuthorized(force: Bool = false) {
        guard !UserDefaults.standard.bool(forKey: Self.locationDeclinedKey) else { return }
        guard force || shouldAttemptWeatherFetch(force: false) else { return }

        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if let location = locationManager.location {
                startWeatherFetch(for: location, force: force)
            } else if force || !pendingLocationRequest {
                pendingLocationRequest = true
                isLoading = true
                locationManager.requestLocation()
            }
        case .denied, .restricted, .notDetermined:
            weather = nil
            isLoading = false
        @unknown default:
            break
        }
    }

    private func shouldAttemptWeatherFetch(force: Bool) -> Bool {
        if force { return true }
        if isFetchingWeather || pendingLocationRequest { return false }
        if weather != nil,
           let lastSuccessfulFetchAt,
           Date().timeIntervalSince(lastSuccessfulFetchAt) < Self.weatherRefreshInterval {
            return false
        }
        return true
    }

    private func startWeatherFetch(for location: CLLocation, force: Bool = false) {
        if isFetchingWeather, !force { return }

        pendingLocationRequest = false
        weatherFetchGeneration += 1
        let generation = weatherFetchGeneration
        weatherFetchTask?.cancel()
        weatherFetchTask = Task { @MainActor in
            await fetchWeather(for: location, generation: generation)
        }
    }

    private func fetchWeather(for location: CLLocation, generation: Int) async {
        isFetchingWeather = true
        isLoading = true
        statusMessage = nil
        defer {
            if generation == weatherFetchGeneration {
                isLoading = false
                isFetchingWeather = false
            }
        }

        do {
            let forecast = try await weatherService.weather(for: location)
            guard !Task.isCancelled, generation == weatherFetchGeneration else { return }

            let locationContext = await Self.resolveLocationContext(for: location)
            let fallbackCityName = await Self.resolveCityName(for: location)
            let cityName = locationContext?.localityName
                ?? locationContext?.subdivisionName
                ?? fallbackCityName
            guard !Task.isCancelled, generation == weatherFetchGeneration else { return }

            weather = Self.makeTodayWeather(from: forecast, cityName: cityName)
            lastSuccessfulFetchAt = Date()
            let countryCode = locationContext?.countryCode ?? Self.fallbackCountryCode()
            DashboardPublicHolidayService.shared.refresh(
                countryCode: countryCode,
                subdivisionCode: locationContext?.subdivisionCode,
                locationLabel: locationContext?.dashboardLocationLabel
            )
        } catch {
            guard !Task.isCancelled, generation == weatherFetchGeneration else { return }
            weather = nil
            statusMessage = Self.userMessage(for: error)
            logger.error("WeatherKit fetch failed: \(String(describing: error), privacy: .public)")
        }
    }

    private static let settingsSteps = [
        "Open Settings (tap Open Settings below).",
        "Go to Privacy & Security → Location Services.",
        "Turn on Location Services if it is off.",
        "Find Nucleus in the list and choose While Using the App.",
        "Return to Nucleus — the forecast appears automatically.",
    ]

    private static let firstRequestSteps = [
        "Tap Enable Location below.",
        "When iOS asks, choose Allow While Using App.",
        "Return here to see today's forecast.",
    ]

    private static let restrictedSteps = [
        "Open Settings → Privacy & Security → Location Services.",
        "If Nucleus appears in the list, enable location access.",
        "If access stays blocked, this device may be managed by work or school policy.",
    ]

    private static func userMessage(for error: Error) -> String {
        if let weatherError = error as? WeatherError {
            switch weatherError {
            case .permissionDenied:
                return "WeatherKit is not active for Nucleus yet. In Apple Developer, open the \(NucleusAppIdentity.bundleIdentifier) App ID, enable WeatherKit under App Services, wait about 30 minutes, then rebuild."
            case .unknown:
                break
            @unknown default:
                break
            }
        }

        let description = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let combined = "\(error) \(description)".lowercased()
        if combined.contains("jwt")
            || combined.contains("weatherdaemon")
            || combined.contains("authservice")
            || combined.contains("permission")
            || combined.contains("401")
            || combined.contains("unauthorized") {
            return "WeatherKit authentication failed. Enable WeatherKit under App Services for \(NucleusAppIdentity.bundleIdentifier) in Apple Developer, then rebuild."
        }
        if combined.contains("network") || combined.contains("offline") || combined.contains("internet") {
            return "Could not reach Apple's weather service. Check your internet connection and try again."
        }
        if combined.contains("unavailable") || combined.contains("server") {
            return "Apple's weather service is temporarily unavailable. Try again shortly."
        }

        return "Weather is unavailable right now."
    }

    private static func resolveCityName(for location: CLLocation) async -> String? {
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return nil }
            if let locality = placemark.locality, !locality.isEmpty {
                return locality
            }
            if let area = placemark.administrativeArea, !area.isEmpty {
                return area
            }
            return placemark.name
        } catch {
            return nil
        }
    }

    private static func resolveLocationContext(for location: CLLocation) async -> DashboardLocationContext? {
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return nil }
            return DashboardLocationSubdivisionResolver.context(from: placemark)
        } catch {
            return nil
        }
    }

    private static func resolveCountryCode(for location: CLLocation) async -> String? {
        await resolveLocationContext(for: location)?.countryCode
    }

    private static func fallbackCountryCode() -> String? {
        Locale.current.region?.identifier.uppercased()
    }

    private static func makeTodayWeather(from weather: Weather, cityName: String?) -> DashboardTodayWeather {
        let calendar = Calendar.current
        let now = Date()
        let today = weather.dailyForecast.first { day in
            calendar.isDate(day.date, inSameDayAs: now)
        } ?? weather.dailyForecast.first

        let formatter = MeasurementFormatter()
        formatter.numberFormatter.maximumFractionDigits = 0
        formatter.unitOptions = .providedUnit

        let high = today.map { formatter.string(from: $0.highTemperature) } ?? "—"
        let low = today.map { formatter.string(from: $0.lowTemperature) } ?? "—"
        let condition = today?.condition ?? weather.currentWeather.condition

        return DashboardTodayWeather(
            cityName: cityName,
            conditionSymbol: symbolName(for: condition),
            conditionDescription: condition.description,
            highTemperature: high,
            lowTemperature: low,
            rainSummary: rainSummary(from: weather, now: now, calendar: calendar),
            dailyForecast: makeDailyForecast(from: weather, now: now, calendar: calendar, formatter: formatter)
        )
    }

    private static func makeDailyForecast(
        from weather: Weather,
        now: Date,
        calendar: Calendar,
        formatter: MeasurementFormatter
    ) -> [DashboardDailyWeatherForecast] {
        let dayNameFormatter = DateFormatter()
        dayNameFormatter.dateFormat = "EEE"

        return weather.dailyForecast
            .filter { !calendar.isDate($0.date, inSameDayAs: now) }
            .prefix(7)
            .map { day in
                DashboardDailyWeatherForecast(
                    date: day.date,
                    dayLabel: dayNameFormatter.string(from: day.date),
                    conditionSymbol: symbolName(for: day.condition),
                    highTemperature: formatter.string(from: day.highTemperature),
                    lowTemperature: formatter.string(from: day.lowTemperature)
                )
            }
    }

    private static func rainSummary(from weather: Weather, now: Date, calendar: Calendar) -> String? {
        let rainyHours = weather.hourlyForecast.filter { hour in
            guard calendar.isDate(hour.date, inSameDayAs: now), hour.date >= now else { return false }
            return hour.precipitationChance >= 0.25 || isRainy(hour)
        }

        guard let first = rainyHours.first else {
            return "No rain expected for the rest of today."
        }

        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none

        if rainyHours.count == 1 {
            return "Rain around \(timeFormatter.string(from: first.date))."
        }

        if let last = rainyHours.last {
            return "Rain expected \(timeFormatter.string(from: first.date))–\(timeFormatter.string(from: last.date))."
        }

        return "Rain expected around \(timeFormatter.string(from: first.date))."
    }

    private static func isRainy(_ hour: HourWeather) -> Bool {
        switch hour.condition {
        case .rain, .drizzle, .heavyRain, .freezingRain, .freezingDrizzle, .sunShowers,
             .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms, .thunderstorms:
            return true
        default:
            return false
        }
    }

    private static func symbolName(for condition: WeatherCondition) -> String {
        switch condition {
        case .clear, .mostlyClear, .hot, .frigid:
            return "sun.max.fill"
        case .partlyCloudy:
            return "cloud.sun.fill"
        case .cloudy, .mostlyCloudy:
            return "cloud.fill"
        case .rain, .drizzle, .heavyRain, .freezingRain, .freezingDrizzle, .sunShowers:
            return "cloud.rain.fill"
        case .snow, .flurries, .heavySnow, .sleet, .blizzard, .blowingSnow, .sunFlurries, .wintryMix:
            return "cloud.snow.fill"
        case .foggy, .haze, .smoky:
            return "cloud.fog.fill"
        case .windy, .breezy, .blowingDust:
            return "wind"
        case .hail, .hurricane, .tropicalStorm:
            return "cloud.bolt.rain.fill"
        case .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms, .thunderstorms:
            return "cloud.bolt.fill"
        @unknown default:
            return "cloud.sun.fill"
        }
    }
}

extension MobileDashboardWeatherService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
                UserDefaults.standard.set(true, forKey: Self.locationPromptCompletedKey)
            }
            requestWeatherIfAuthorized()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            pendingLocationRequest = false
            startWeatherFetch(for: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            pendingLocationRequest = false
            isLoading = false
            if weather == nil {
                statusMessage = "Couldn't determine your location for weather."
            }
            logger.error("Location request failed: \(String(describing: error), privacy: .public)")
        }
    }
}
