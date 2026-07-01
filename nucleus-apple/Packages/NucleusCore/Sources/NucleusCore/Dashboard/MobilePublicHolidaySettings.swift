import Foundation
import SwiftUI

@MainActor
public final class MobilePublicHolidaySettings: ObservableObject {
    public static let shared = MobilePublicHolidaySettings()

    private static let countryCodesKey = "nucleus.settings.publicHolidayCountryCodes"

    @Published public var companionCountryCodes: [String] {
        didSet {
            let normalized = DashboardPublicHolidayService.normalizedCountryCodes(companionCountryCodes)
            if normalized != companionCountryCodes {
                companionCountryCodes = normalized
                return
            }
            UserDefaults.standard.set(normalized, forKey: Self.countryCodesKey)
        }
    }

    private init() {
        companionCountryCodes = UserDefaults.standard.stringArray(forKey: Self.countryCodesKey) ?? []
    }

    public func binding(for countryCode: String) -> Binding<Bool> {
        Binding(
            get: { self.companionCountryCodes.contains(countryCode.uppercased()) },
            set: { isSelected in
                var codes = self.companionCountryCodes
                let normalized = countryCode.uppercased()
                if isSelected {
                    guard !codes.contains(normalized) else { return }
                    codes.append(normalized)
                    self.companionCountryCodes = DashboardPublicHolidayService.normalizedCountryCodes(codes)
                } else {
                    self.companionCountryCodes = codes.filter { $0 != normalized }
                }
            }
        )
    }

    public func clearCompanionCountries() {
        companionCountryCodes = []
    }
}
