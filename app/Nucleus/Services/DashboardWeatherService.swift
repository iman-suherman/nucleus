import AppKit
import CoreLocation
import Foundation
import OSLog
import WeatherKit

struct DashboardTodayWeather: Equatable {
    var cityName: String?
    var conditionSymbol: String
    var conditionDescription: String
    var highTemperature: String
    var lowTemperature: String
    var rainSummary: String?
    var dailyForecast: [DashboardDailyWeatherForecast]
}

struct DashboardDailyWeatherForecast: Equatable, Identifiable {
    var date: Date
    var dayLabel: String
    var conditionSymbol: String
    var highTemperature: String
    var lowTemperature: String

    var id: Date { date }
}

struct DashboardWeatherLocationSnapshot: Equatable {
    var countryCode: String
    var subdivisionCode: String?
    var locationLabel: String?
}

struct DashboardWeatherLocationPrompt: Equatable {
    enum Action: Equatable {
        case requestAuthorization
        case openSettings
        case reenableAfterDecline
    }

    let message: String
    let steps: [String]
    let buttonTitle: String
    let action: Action
}

enum DashboardGreeting {
    static var firstName: String {
        let fullName = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = fullName.split(separator: " ").first, !first.isEmpty {
            return String(first)
        }

        let shortName = NSUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        return shortName.isEmpty ? "there" : shortName
    }

    static func timeOfDay(now: Date = Date(), calendar: Calendar = .current) -> String {
        timeOfDay(for: DashboardTimePeriod.current(now: now, calendar: calendar))
    }

    static func timeOfDay(for period: DashboardTimePeriod) -> String {
        switch period {
        case .morning: return "Good morning"
        case .afternoon: return "Good afternoon"
        case .evening: return "Good evening"
        case .night: return "Good night"
        }
    }

    static func isWeekend(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        calendar.isDateInWeekend(now)
    }

    static func line(
        firstName: String,
        now: Date = Date(),
        calendar: Calendar = .current,
        isPublicHoliday: Bool = false,
        publicHolidayName: String? = nil
    ) -> String {
        let weekend = isWeekend(now: now, calendar: calendar)

        if isPublicHoliday {
            if let publicHolidayName, !publicHolidayName.isEmpty {
                return "Happy \(publicHolidayName), \(firstName)!"
            }
            if weekend {
                return "Happy holiday weekend, \(firstName)!"
            }
            return "Happy holiday, \(firstName)!"
        }

        if weekend {
            return "Happy weekend, \(firstName)!"
        }

        return "\(timeOfDay(now: now, calendar: calendar)), \(firstName)!"
    }
}

@MainActor
final class DashboardWeatherService: NSObject, ObservableObject {
    static let shared = DashboardWeatherService()

    private static let locationPromptCompletedKey = "nucleus.weather.locationPromptCompleted"
    private static let locationDeclinedKey = "nucleus.weather.locationDeclined"

    @Published private(set) var weather: DashboardTodayWeather?
    @Published private(set) var locationSnapshot: DashboardWeatherLocationSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var statusMessage: String?
    @Published var showLocationPermissionPrompt = false

    /// When false, the Dashboard hides Today's weather entirely.
    @Published private(set) var isWeatherSectionVisible = false
    @Published private(set) var showsManualLocationEntry = false
    @Published var manualLocationDraft = ""

    /// True while waiting on Core Location (including retry backoff), before weather fetch starts.
    var isAwaitingDeviceLocation: Bool {
        (pendingLocationRequest || locationRetryTask != nil) && !isFetchingWeather && weather == nil
    }

    private let weatherService = WeatherService.shared
    private let locationManager = CLLocationManager()
    private let logger = Logger(subsystem: "net.suherman.nucleus", category: "DashboardWeather")
    private var hasStarted = false
    private var pendingLocationRequest = false
    private var queuedForcedLocationRefresh = false
    private var locationRetryCount = 0
    private var locationRetryTask: Task<Void, Never>?
    private var weatherFetchTask: Task<Void, Never>?
    private var isFetchingWeather = false
    private var weatherFetchGeneration = 0
    private var lastSuccessfulFetchAt: Date?
    private var manualLocationRevealTask: Task<Void, Never>?
    private var manualLocationRequestGeneration = 0

    private static let maxLocationRetries = 2
    private static let locationRetryDelay: Duration = .seconds(2)
    private static let manualLocationRevealDelay: Duration = .seconds(5)
    private static let weatherRefreshInterval: TimeInterval = 15 * 60

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        updateWeatherSectionVisibility()
    }

    func beginWeatherAccessFlow() {
        updateWeatherSectionVisibility()

        guard isWeatherSectionVisible || shouldOfferLocationPrompt else { return }

        guard !hasStarted else {
            guard shouldAttemptWeatherFetch(force: false) else { return }
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

    func retryWeatherFetch() {
        locationRetryCount = 0
        locationRetryTask?.cancel()
        locationRetryTask = nil
        statusMessage = nil

        if pendingLocationRequest {
            queueForcedLocationRefreshIfNeeded()
            return
        }

        requestWeatherIfAuthorized(force: true)
    }

    func submitManualLocation() {
        let query = manualLocationDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        manualLocationRequestGeneration += 1
        let generation = manualLocationRequestGeneration
        pendingLocationRequest = false
        queuedForcedLocationRefresh = false
        locationRetryTask?.cancel()
        locationRetryTask = nil
        endLocationLookupUI()

        isLoading = true
        statusMessage = nil

        Task { @MainActor in
            await resolveManualLocation(query: query, generation: generation)
        }
    }

    func declineLocationPermission() {
        UserDefaults.standard.set(true, forKey: Self.locationPromptCompletedKey)
        UserDefaults.standard.set(true, forKey: Self.locationDeclinedKey)
        showLocationPermissionPrompt = false
        weather = nil
        isLoading = false
        statusMessage = nil
        updateWeatherSectionVisibility()
    }

    func refreshIfNeeded() {
        guard shouldAttemptWeatherFetch(force: false) else { return }
        beginWeatherAccessFlow()
    }

    private func shouldAttemptWeatherFetch(force: Bool) -> Bool {
        if force { return true }
        if isFetchingWeather || pendingLocationRequest { return false }
        if weather != nil,
           let lastSuccessfulFetchAt,
           Date().timeIntervalSince(lastSuccessfulFetchAt) < Self.weatherRefreshInterval {
            return false
        }
        if weather == nil, Self.isWeatherKitErrorMessage(statusMessage) {
            return false
        }
        return true
    }

    func openLocationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Shown in the Dashboard weather card when location access prevents a forecast.
    var locationAccessPrompt: DashboardWeatherLocationPrompt? {
        guard !isWeatherSectionVisible else { return nil }

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
                message: "Location access is restricted on this Mac, so today's weather can't be shown.",
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
        case .authorized, .authorizedAlways:
            return nil
        @unknown default:
            return nil
        }
    }

    private static let settingsSteps = [
        "Open System Settings (click Open Settings below).",
        "Go to Privacy & Security → Location Services.",
        "Turn on Location Services if it is off.",
        "Find Nucleus in the list and enable location access.",
        "Return to Nucleus — the forecast appears here automatically.",
    ]

    private static let firstRequestSteps = [
        "Click Enable Location below.",
        "When macOS asks, choose Allow.",
        "If no prompt appears, open System Settings → Privacy & Security → Location Services.",
        "Turn on Location Services, then enable Nucleus.",
        "Return here to see today's forecast.",
    ]

    private static let restrictedSteps = [
        "Open System Settings → Privacy & Security → Location Services.",
        "If Nucleus appears in the list, enable location access.",
        "If access stays blocked, your Mac may be managed by work or school policy.",
    ]

    func performLocationAccessAction(_ action: DashboardWeatherLocationPrompt.Action) {
        switch action {
        case .requestAuthorization:
            confirmLocationPermissionRequest()
        case .openSettings:
            openLocationSettings()
        case .reenableAfterDecline:
            UserDefaults.standard.set(false, forKey: Self.locationDeclinedKey)
            UserDefaults.standard.set(false, forKey: Self.locationPromptCompletedKey)
            updateWeatherSectionVisibility()
            hasStarted = false
            beginWeatherAccessFlow()
        }
    }

    private var shouldOfferLocationPrompt: Bool {
        !UserDefaults.standard.bool(forKey: Self.locationPromptCompletedKey)
            && !UserDefaults.standard.bool(forKey: Self.locationDeclinedKey)
            && locationManager.authorizationStatus == .notDetermined
    }

    private func updateWeatherSectionVisibility() {
        if UserDefaults.standard.bool(forKey: Self.locationDeclinedKey) {
            isWeatherSectionVisible = false
            return
        }

        switch locationManager.authorizationStatus {
        case .authorized, .authorizedAlways:
            isWeatherSectionVisible = true
        case .denied, .restricted:
            isWeatherSectionVisible = false
        case .notDetermined:
            isWeatherSectionVisible = false
        @unknown default:
            isWeatherSectionVisible = false
        }
    }

    private func requestWeatherIfAuthorized(force: Bool = false) {
        updateWeatherSectionVisibility()
        guard isWeatherSectionVisible else { return }
        guard force || shouldAttemptWeatherFetch(force: false) else { return }

        switch locationManager.authorizationStatus {
        case .authorized, .authorizedAlways:
            if let location = locationManager.location {
                if pendingLocationRequest, force {
                    queueForcedLocationRefreshIfNeeded()
                    return
                }
                startWeatherFetch(for: location, force: force)
            } else if pendingLocationRequest {
                if force {
                    queueForcedLocationRefreshIfNeeded()
                }
            } else {
                requestSingleLocationUpdate()
            }
        case .denied, .restricted, .notDetermined:
            weather = nil
            isLoading = false
            statusMessage = nil
            updateWeatherSectionVisibility()
        @unknown default:
            break
        }
    }

    private func queueForcedLocationRefreshIfNeeded() {
        queuedForcedLocationRefresh = true
        isLoading = true
        if !Self.isWeatherKitErrorMessage(statusMessage) {
            statusMessage = "Finding your location…"
        }
        scheduleManualLocationEntryRevealIfNeeded()
        logger.debug("Location request already in flight; queued forced refresh")
    }

    private func scheduleManualLocationEntryRevealIfNeeded() {
        guard manualLocationRevealTask == nil else { return }

        manualLocationRevealTask = Task { @MainActor in
            try? await Task.sleep(for: Self.manualLocationRevealDelay)
            guard !Task.isCancelled, isAwaitingDeviceLocation else { return }
            showsManualLocationEntry = true
        }
    }

    private func endLocationLookupUI() {
        manualLocationRevealTask?.cancel()
        manualLocationRevealTask = nil
        showsManualLocationEntry = false
    }

    private func requestSingleLocationUpdate() {
        guard !pendingLocationRequest else { return }

        pendingLocationRequest = true
        isLoading = true
        if !Self.isWeatherKitErrorMessage(statusMessage) {
            statusMessage = "Finding your location…"
        }
        scheduleManualLocationEntryRevealIfNeeded()
        locationManager.requestLocation()
    }

    private func scheduleLocationRetry() {
        locationRetryTask?.cancel()
        locationRetryTask = Task { @MainActor in
            try? await Task.sleep(for: Self.locationRetryDelay)
            guard !Task.isCancelled else { return }
            requestSingleLocationUpdate()
        }
    }

    private func startWeatherFetch(for location: CLLocation, force: Bool = false) {
        if isFetchingWeather, !force { return }

        locationRetryTask?.cancel()
        locationRetryTask = nil
        locationRetryCount = 0
        pendingLocationRequest = false
        endLocationLookupUI()

        weatherFetchGeneration += 1
        let generation = weatherFetchGeneration
        weatherFetchTask?.cancel()
        weatherFetchTask = Task { @MainActor in
            await fetchWeather(for: location, generation: generation)
        }
    }

    private func handleLocationFailure(_ error: Error) {
        pendingLocationRequest = false

        if queuedForcedLocationRefresh {
            queuedForcedLocationRefresh = false
            locationRetryCount = 0
            locationRetryTask?.cancel()
            locationRetryTask = nil
            requestSingleLocationUpdate()
            return
        }

        if isFetchingWeather {
            logger.warning("Ignoring location failure during active weather fetch")
            return
        }

        if Self.isWeatherKitErrorMessage(statusMessage) {
            logger.warning("Keeping WeatherKit error after location failure")
            isLoading = false
            return
        }

        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                weather = nil
                isLoading = false
                statusMessage = "Allow location access in System Settings to show today's weather."
                logger.error("Location denied: \(String(describing: error), privacy: .public)")
                return
            case .locationUnknown, .network:
                if locationRetryCount < Self.maxLocationRetries {
                    locationRetryCount += 1
                    logger.info("Retrying location request (\(self.locationRetryCount)/\(Self.maxLocationRetries))")
                    statusMessage = "Finding your location…"
                    isLoading = true
                    scheduleLocationRetry()
                    return
                }
            default:
                break
            }
        }

        weather = nil
        isLoading = false
        endLocationLookupUI()
        statusMessage = Self.locationFailureMessage(for: error)
        logger.error("Location request failed: \(String(describing: error), privacy: .public)")
    }

    private func resolveManualLocation(query: String, generation: Int) async {
        defer {
            if generation == manualLocationRequestGeneration, weather == nil, !isFetchingWeather {
                isLoading = isAwaitingDeviceLocation
            }
        }

        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.geocodeAddressString(query)
            guard generation == manualLocationRequestGeneration else { return }
            guard let location = placemarks.first?.location else {
                isLoading = false
                statusMessage = "Couldn't find that place. Try a city name or postcode."
                showsManualLocationEntry = true
                return
            }
            manualLocationDraft = query
            startWeatherFetch(for: location, force: true)
        } catch {
            guard generation == manualLocationRequestGeneration else { return }
            isLoading = false
            statusMessage = "Couldn't find that place. Try a city name or postcode."
            showsManualLocationEntry = true
            logger.error("Manual location geocode failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func handleAuthorizationChange() {
        if locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
            UserDefaults.standard.set(true, forKey: Self.locationPromptCompletedKey)
        }
        updateWeatherSectionVisibility()
        requestWeatherIfAuthorized()
    }

    private func fetchWeather(for location: CLLocation, generation: Int) async {
        isFetchingWeather = true
        isLoading = true
        if !Self.isWeatherKitErrorMessage(statusMessage) {
            statusMessage = nil
        }
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
            statusMessage = nil
            lastSuccessfulFetchAt = Date()

            let countryCode = locationContext?.countryCode ?? Self.fallbackCountryCode()
            if let countryCode {
                locationSnapshot = DashboardWeatherLocationSnapshot(
                    countryCode: countryCode,
                    subdivisionCode: locationContext?.subdivisionCode,
                    locationLabel: locationContext?.dashboardLocationLabel
                )
            }
        } catch {
            guard !Task.isCancelled, generation == weatherFetchGeneration else { return }

            weather = nil
            statusMessage = Self.userMessage(for: error)
            logger.error("WeatherKit fetch failed: \(String(describing: error), privacy: .public)")
        }
    }

    private static func isWeatherKitErrorMessage(_ message: String?) -> Bool {
        guard let message else { return false }
        let lower = message.lowercased()
        return lower.contains("weatherkit")
            || lower.contains("weather service")
            || lower.contains("apple's weather")
    }

    private static func locationFailureMessage(for error: Error) -> String {
        if let clError = error as? CLError {
            switch clError.code {
            case .network:
                return "Location lookup needs a network connection. Check Wi‑Fi and try again."
            case .locationUnknown:
                return "Couldn't determine your location yet. Try again in a moment."
            default:
                break
            }
        }
        return "Couldn't determine your location for weather."
    }

    private static func userMessage(for error: Error) -> String {
        if let weatherError = error as? WeatherError {
            switch weatherError {
            case .permissionDenied:
                return "WeatherKit is not active for Nucleus yet. In Apple Developer, open the net.suherman.nucleus App ID, enable WeatherKit under App Services, wait about 30 minutes, then rebuild."
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
            return "WeatherKit authentication failed. Enable WeatherKit under App Services for net.suherman.nucleus in Apple Developer, then rebuild."
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
        let description = condition.description

        let dayNameFormatter = DateFormatter()
        dayNameFormatter.dateFormat = "EEE"

        let dailyForecast = weather.dailyForecast
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

        return DashboardTodayWeather(
            cityName: cityName,
            conditionSymbol: symbolName(for: condition),
            conditionDescription: description,
            highTemperature: high,
            lowTemperature: low,
            rainSummary: rainSummary(from: weather, now: now, calendar: calendar),
            dailyForecast: Array(dailyForecast)
        )
    }

    private static func rainSummary(from weather: Weather, now: Date, calendar: Calendar) -> String? {
        let rainyHours = weather.hourlyForecast.filter { hour in
            guard calendar.isDate(hour.date, inSameDayAs: now), hour.date >= now else { return false }
            return isRainy(hour)
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

        if let last = rainyHours.last, calendar.component(.hour, from: first.date) != calendar.component(.hour, from: last.date) {
            return "Rain expected \(timeFormatter.string(from: first.date))–\(timeFormatter.string(from: last.date))."
        }

        return "Rain expected around \(timeFormatter.string(from: first.date))."
    }

    private static func isRainy(_ hour: HourWeather) -> Bool {
        if hour.precipitationChance >= 0.25 {
            return true
        }

        switch hour.condition {
        case .rain, .drizzle, .heavyRain, .freezingRain, .freezingDrizzle, .sunShowers, .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms, .thunderstorms:
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

extension DashboardWeatherService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            handleAuthorizationChange()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            guard pendingLocationRequest else { return }
            pendingLocationRequest = false
            queuedForcedLocationRefresh = false
            locationRetryCount = 0
            locationRetryTask?.cancel()
            locationRetryTask = nil
            endLocationLookupUI()
            startWeatherFetch(for: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            handleLocationFailure(error)
        }
    }
}
