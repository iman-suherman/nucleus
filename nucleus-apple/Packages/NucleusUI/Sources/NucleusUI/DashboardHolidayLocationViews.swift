import NucleusCore
import SwiftUI

public struct DashboardHolidayLocationCard: View {
    @ObservedObject private var locationService: DashboardLocationService

    public init(locationService: DashboardLocationService = .shared) {
        self.locationService = locationService
    }

    public var body: some View {
        if shouldShowLocationPrompt {
            VStack(alignment: .leading, spacing: 10) {
                Text(promptMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                locationActionButton
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .tint(.accentColor)

                if let statusMessage = locationService.statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var shouldShowLocationPrompt: Bool {
        !locationService.hasUserSelectedLocation || locationService.locationAccessPrompt != nil
    }

    private var promptMessage: String {
        if let prompt = locationService.locationAccessPrompt {
            return prompt.message
        }
        if locationService.resolvedLocationDescription != "Not set" {
            return "Showing holidays for \(locationService.resolvedLocationDescription) from your device region. Set your current location for local state and regional holidays."
        }
        return "Set your current location to show local state and regional public holidays."
    }

    @ViewBuilder
    private var locationActionButton: some View {
        if let prompt = locationService.locationAccessPrompt {
            Button {
                locationService.performLocationAccessAction(prompt.action)
            } label: {
                Label(prompt.buttonTitle, systemImage: "location.fill")
                    .frame(maxWidth: .infinity)
            }
        } else {
            Button {
                locationService.useDeviceLocation()
            } label: {
                if locationService.isResolving {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Set my location", systemImage: "location.fill")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(locationService.isResolving)
        }
    }
}

public struct PublicHolidayLocationSettingsSection: View {
    @ObservedObject private var locationService: DashboardLocationService

    public init(locationService: DashboardLocationService = .shared) {
        self.locationService = locationService
    }

    public var body: some View {
        Section("Holiday location") {
            LabeledContent("Current place", value: locationService.resolvedLocationDescription)

            if locationService.usesManualLocation {
                Text("Custom place")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if locationService.hasUserSelectedLocation {
                Text("Using your saved device location")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let region = Locale.current.region?.identifier {
                Text("Using device region · \(DashboardPublicHolidayCountryCatalog.localizedCountryName(for: region)) until a place is set.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let prompt = locationService.locationAccessPrompt {
                Button(prompt.buttonTitle) {
                    locationService.performLocationAccessAction(prompt.action)
                }
            }

            Button {
                locationService.useDeviceLocation()
            } label: {
                Label("Set my location", systemImage: "location.fill")
            }
            .disabled(locationService.isResolving)

            TextField("City or postcode", text: $locationService.manualLocationDraft)
                .textInputAutocapitalization(.words)
                .submitLabel(.search)
                .onSubmit {
                    locationService.submitManualLocation()
                }

            Button("Choose another place") {
                locationService.submitManualLocation()
            }
            .disabled(
                locationService.isResolving
                    || locationService.manualLocationDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )

            if let statusMessage = locationService.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Choose another place for state and regional public holidays. Set my location saves your GPS position on this device.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            locationService.beginLocationUpdatesIfNeeded()
        }
    }
}

public struct PublicHolidayCountrySettingsSection: View {
    @ObservedObject private var settings: MobilePublicHolidaySettings
    @State private var countries: [DashboardPublicHolidayCountryOption] = []
    @State private var countryFilter = ""

    public init(settings: MobilePublicHolidaySettings = .shared) {
        self.settings = settings
    }

    public var body: some View {
        Section("More holiday locations") {
            Text("Choose up to \(DashboardPublicHolidayService.maxSelectedCountries) countries to show alongside your location on the Dashboard.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Search countries", text: $countryFilter)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            let filteredCountries = filteredPublicHolidayCountries
            if filteredCountries.isEmpty {
                Text("No countries match your search.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredCountries) { country in
                    Toggle(isOn: settings.binding(for: country.countryCode)) {
                        Text(country.name)
                    }
                    .disabled(
                        !settings.companionCountryCodes.contains(country.countryCode)
                            && settings.companionCountryCodes.count >= DashboardPublicHolidayService.maxSelectedCountries
                    )
                }
            }

            if !settings.companionCountryCodes.isEmpty {
                Button("Clear selected countries", role: .destructive) {
                    settings.clearCompanionCountries()
                }
            }
        }
        .task {
            countries = await DashboardPublicHolidayCountryCatalog.fetchCountries()
        }
    }

    private var filteredPublicHolidayCountries: [DashboardPublicHolidayCountryOption] {
        let query = countryFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return countries }
        return countries.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.countryCode.localizedCaseInsensitiveContains(query)
        }
    }
}
