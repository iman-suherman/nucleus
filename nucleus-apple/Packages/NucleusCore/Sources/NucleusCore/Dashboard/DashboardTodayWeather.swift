import Foundation

public struct DashboardDailyWeatherForecast: Equatable, Sendable, Identifiable {
    public var date: Date
    public var dayLabel: String
    public var conditionSymbol: String
    public var highTemperature: String
    public var lowTemperature: String

    public var id: Date { date }

    public init(
        date: Date,
        dayLabel: String,
        conditionSymbol: String,
        highTemperature: String,
        lowTemperature: String
    ) {
        self.date = date
        self.dayLabel = dayLabel
        self.conditionSymbol = conditionSymbol
        self.highTemperature = highTemperature
        self.lowTemperature = lowTemperature
    }
}

public struct DashboardTodayWeather: Equatable, Sendable {
    public var cityName: String?
    public var conditionSymbol: String
    public var conditionDescription: String
    public var highTemperature: String
    public var lowTemperature: String
    public var rainSummary: String?
    public var dailyForecast: [DashboardDailyWeatherForecast]

    public init(
        cityName: String?,
        conditionSymbol: String,
        conditionDescription: String,
        highTemperature: String,
        lowTemperature: String,
        rainSummary: String?,
        dailyForecast: [DashboardDailyWeatherForecast] = []
    ) {
        self.cityName = cityName
        self.conditionSymbol = conditionSymbol
        self.conditionDescription = conditionDescription
        self.highTemperature = highTemperature
        self.lowTemperature = lowTemperature
        self.rainSummary = rainSummary
        self.dailyForecast = dailyForecast
    }
}

public struct DashboardWeatherLocationPrompt: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case requestAuthorization
        case openSettings
        case reenableAfterDecline
    }

    public let message: String
    public let steps: [String]
    public let buttonTitle: String
    public let action: Action

    public init(
        message: String,
        steps: [String],
        buttonTitle: String,
        action: Action
    ) {
        self.message = message
        self.steps = steps
        self.buttonTitle = buttonTitle
        self.action = action
    }
}
