import Foundation

public struct DashboardTodayWeather: Equatable, Sendable {
    public var cityName: String?
    public var conditionSymbol: String
    public var conditionDescription: String
    public var highTemperature: String
    public var lowTemperature: String
    public var rainSummary: String?

    public init(
        cityName: String?,
        conditionSymbol: String,
        conditionDescription: String,
        highTemperature: String,
        lowTemperature: String,
        rainSummary: String?
    ) {
        self.cityName = cityName
        self.conditionSymbol = conditionSymbol
        self.conditionDescription = conditionDescription
        self.highTemperature = highTemperature
        self.lowTemperature = lowTemperature
        self.rainSummary = rainSummary
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
