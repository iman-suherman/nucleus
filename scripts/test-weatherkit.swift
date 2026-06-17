import CoreLocation
import Foundation
import WeatherKit

@MainActor
func run() async {
    let location = CLLocation(latitude: -33.8688, longitude: 151.2093)
    do {
        let weather = try await WeatherService.shared.weather(for: location)
        let condition = weather.currentWeather.condition.description
        let high = weather.dailyForecast.first?.highTemperature
        print("WEATHERKIT_OK condition=\(condition) high=\(String(describing: high))")
        exit(0)
    } catch {
        fputs("WEATHERKIT_FAILED \(error)\n", stderr)
        exit(1)
    }
}

Task { await run() }
dispatchMain()
