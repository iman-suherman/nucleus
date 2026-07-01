import Foundation

public struct DashboardLocationSnapshot: Equatable, Sendable {
    public var countryCode: String
    public var subdivisionCode: String?
    public var locationLabel: String?

    public init(countryCode: String, subdivisionCode: String? = nil, locationLabel: String? = nil) {
        self.countryCode = countryCode.uppercased()
        self.subdivisionCode = subdivisionCode?.uppercased()
        self.locationLabel = locationLabel
    }
}
