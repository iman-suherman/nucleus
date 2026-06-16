import AppKit
import CoreLocation
import Foundation
import WeatherKit

struct DashboardTodayWeather: Equatable {
    var conditionSymbol: String
    var conditionDescription: String
    var highTemperature: String
    var lowTemperature: String
    var rainSummary: String?
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
        let hour = calendar.component(.hour, from: now)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good evening"
        }
    }
}

@MainActor
final class DashboardWeatherService: NSObject, ObservableObject {
    static let shared = DashboardWeatherService()

    @Published private(set) var weather: DashboardTodayWeather?
    @Published private(set) var isLoading = false
    @Published private(set) var statusMessage: String?

    private let weatherService = WeatherService.shared
    private let locationManager = CLLocationManager()
    private var hasStarted = false

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func refreshIfNeeded() {
        guard !hasStarted else {
            requestWeatherIfAuthorized()
            return
        }
        hasStarted = true
        statusMessage = "Waiting for location access…"
        locationManager.requestWhenInUseAuthorization()
        requestWeatherIfAuthorized()
    }

    func openLocationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    private func requestWeatherIfAuthorized() {
        switch locationManager.authorizationStatus {
        case .authorized, .authorizedAlways:
            statusMessage = nil
            if let location = locationManager.location {
                Task { await fetchWeather(for: location) }
            } else {
                isLoading = true
                locationManager.requestLocation()
            }
        case .denied, .restricted:
            weather = nil
            isLoading = false
            statusMessage = "Allow location access in System Settings to show today's weather."
        case .notDetermined:
            isLoading = false
            statusMessage = "Allow location access to show today's weather."
        @unknown default:
            break
        }
    }

    private func fetchWeather(for location: CLLocation) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let forecast = try await weatherService.weather(for: location)
            weather = Self.makeTodayWeather(from: forecast)
            statusMessage = nil
        } catch {
            weather = nil
            statusMessage = "Weather is unavailable right now."
        }
    }

    private static func makeTodayWeather(from weather: Weather) -> DashboardTodayWeather {
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

        return DashboardTodayWeather(
            conditionSymbol: symbolName(for: condition),
            conditionDescription: description,
            highTemperature: high,
            lowTemperature: low,
            rainSummary: rainSummary(from: weather, now: now, calendar: calendar)
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
            requestWeatherIfAuthorized()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            await fetchWeather(for: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            weather = nil
            statusMessage = "Couldn't determine your location for weather."
        }
    }
}
