import CoreLocation
import Foundation

@MainActor
public final class DashboardLocationService: NSObject, ObservableObject {
    public static let shared = DashboardLocationService()

    @Published public private(set) var locationSnapshot: DashboardLocationSnapshot?
    @Published public private(set) var isResolving = false
    @Published public private(set) var statusMessage: String?
    @Published public var manualLocationDraft = ""
    @Published public private(set) var usesManualLocation = false
    @Published public private(set) var hasUserSelectedLocation = false

    private let locationManager = CLLocationManager()
    private var pendingLocationRequest = false
    private var manualRequestGeneration = 0

    private enum StorageKey {
        static let locationSource = "nucleus.mobile.dashboard.locationSource"
        static let usesManualLocation = "nucleus.mobile.dashboard.usesManualLocation"
        static let manualQuery = "nucleus.mobile.dashboard.manualLocationQuery"
        static let snapshotCountry = "nucleus.mobile.dashboard.snapshotCountry"
        static let snapshotSubdivision = "nucleus.mobile.dashboard.snapshotSubdivision"
        static let snapshotLabel = "nucleus.mobile.dashboard.snapshotLabel"
    }

    private enum PersistedLocationSource: String {
        case device
        case manual
    }

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        restorePersistedSnapshot()
    }

    public var resolvedLocationDescription: String {
        if let snapshot = locationSnapshot {
            let country = DashboardPublicHolidayCountryCatalog.localizedCountryName(for: snapshot.countryCode)
            if let label = snapshot.locationLabel, !label.isEmpty {
                return "\(label), \(country)"
            }
            return country
        }
        if let region = Locale.current.region?.identifier {
            return DashboardPublicHolidayCountryCatalog.localizedCountryName(for: region)
        }
        return "Not set"
    }

    public var locationAccessPrompt: DashboardWeatherLocationPrompt? {
        switch locationManager.authorizationStatus {
        case .denied:
            return DashboardWeatherLocationPrompt(
                message: "Allow location access to show public holidays for where you are.",
                steps: [],
                buttonTitle: "Open Settings",
                action: .openSettings
            )
        case .restricted:
            return DashboardWeatherLocationPrompt(
                message: "Location access is restricted on this device.",
                steps: [],
                buttonTitle: "Open Settings",
                action: .openSettings
            )
        case .notDetermined:
            return DashboardWeatherLocationPrompt(
                message: "Use your current location for state and regional public holidays.",
                steps: [],
                buttonTitle: "Enable Location",
                action: .requestAuthorization
            )
        case .authorized, .authorizedAlways:
            return nil
        @unknown default:
            return nil
        }
    }

    public func beginLocationUpdatesIfNeeded() {
        guard !ProcessInfo.processInfo.arguments.contains("-screenshotMode") else {
            applyFallbackRegionIfNeeded()
            return
        }

        if hasUserSelectedLocation {
            return
        }

        switch locationManager.authorizationStatus {
        case .authorized, .authorizedAlways:
            requestDeviceLocation()
        case .notDetermined:
            break
        case .denied, .restricted:
            applyFallbackRegionIfNeeded()
        @unknown default:
            applyFallbackRegionIfNeeded()
        }
    }

    public func requestLocationAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    public func useDeviceLocation() {
        usesManualLocation = false
        statusMessage = nil
        requestDeviceLocation()
    }

    public func submitManualLocation() {
        let query = manualLocationDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        manualRequestGeneration += 1
        let generation = manualRequestGeneration
        pendingLocationRequest = false
        isResolving = true
        statusMessage = nil

        Task { @MainActor in
            await resolveManualLocation(query: query, generation: generation)
        }
    }

    public func performLocationAccessAction(_ action: DashboardWeatherLocationPrompt.Action) {
        switch action {
        case .requestAuthorization:
            requestLocationAuthorization()
        case .openSettings:
            openLocationSettings()
        case .reenableAfterDecline:
            requestLocationAuthorization()
        }
    }

    public func openLocationSettings() {
#if os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
#elseif os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
#endif
    }

    private func requestDeviceLocation() {
        guard !pendingLocationRequest else { return }
        pendingLocationRequest = true
        isResolving = true
        statusMessage = "Finding your location…"
        locationManager.requestLocation()
    }

    private func applyFallbackRegionIfNeeded() {
        guard !hasUserSelectedLocation else { return }
        guard locationSnapshot == nil else { return }
        guard let region = Locale.current.region?.identifier else { return }
        locationSnapshot = DashboardLocationSnapshot(countryCode: region)
    }

    private func resolveManualLocation(query: String, generation: Int) async {
        defer {
            if generation == manualRequestGeneration {
                isResolving = false
            }
        }

        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.geocodeAddressString(query)
            guard generation == manualRequestGeneration else { return }
            guard let placemark = placemarks.first,
                  let context = DashboardLocationSubdivisionResolver.context(from: placemark) else {
                statusMessage = "Couldn't find that place. Try a city name or postcode."
                return
            }

            let snapshot = DashboardLocationSnapshot(
                countryCode: context.countryCode,
                subdivisionCode: context.subdivisionCode,
                locationLabel: context.dashboardLocationLabel
            )
            applySnapshot(snapshot, source: .manual, manualQuery: query)
            statusMessage = nil
        } catch {
            guard generation == manualRequestGeneration else { return }
            statusMessage = "Couldn't find that place. Try a city name or postcode."
        }
    }

    private func resolveDeviceLocation(_ location: CLLocation) async {
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard !usesManualLocation else { return }
            guard let placemark = placemarks.first,
                  let context = DashboardLocationSubdivisionResolver.context(from: placemark) else {
                applyFallbackRegionIfNeeded()
                statusMessage = nil
                return
            }

            let snapshot = DashboardLocationSnapshot(
                countryCode: context.countryCode,
                subdivisionCode: context.subdivisionCode,
                locationLabel: context.dashboardLocationLabel
            )
            applySnapshot(snapshot, source: .device)
            statusMessage = nil
        } catch {
            guard !usesManualLocation else { return }
            applyFallbackRegionIfNeeded()
            statusMessage = nil
        }
    }

    private func applySnapshot(
        _ snapshot: DashboardLocationSnapshot,
        source: PersistedLocationSource,
        manualQuery: String? = nil
    ) {
        locationSnapshot = snapshot
        hasUserSelectedLocation = true
        usesManualLocation = source == .manual

        UserDefaults.standard.set(source.rawValue, forKey: StorageKey.locationSource)
        UserDefaults.standard.set(snapshot.countryCode, forKey: StorageKey.snapshotCountry)
        UserDefaults.standard.set(snapshot.subdivisionCode, forKey: StorageKey.snapshotSubdivision)
        UserDefaults.standard.set(snapshot.locationLabel, forKey: StorageKey.snapshotLabel)
        UserDefaults.standard.set(usesManualLocation, forKey: StorageKey.usesManualLocation)

        if source == .manual, let manualQuery {
            manualLocationDraft = manualQuery
            UserDefaults.standard.set(manualQuery, forKey: StorageKey.manualQuery)
        } else {
            UserDefaults.standard.removeObject(forKey: StorageKey.manualQuery)
        }
    }

    private func restorePersistedSnapshot() {
        let source: PersistedLocationSource?
        if let rawSource = UserDefaults.standard.string(forKey: StorageKey.locationSource),
           let parsed = PersistedLocationSource(rawValue: rawSource) {
            source = parsed
        } else if UserDefaults.standard.bool(forKey: StorageKey.usesManualLocation) {
            source = .manual
        } else {
            source = nil
        }

        guard let source,
              let country = UserDefaults.standard.string(forKey: StorageKey.snapshotCountry) else {
            return
        }

        hasUserSelectedLocation = true
        usesManualLocation = source == .manual
        manualLocationDraft = UserDefaults.standard.string(forKey: StorageKey.manualQuery) ?? ""
        locationSnapshot = DashboardLocationSnapshot(
            countryCode: country,
            subdivisionCode: UserDefaults.standard.string(forKey: StorageKey.snapshotSubdivision),
            locationLabel: UserDefaults.standard.string(forKey: StorageKey.snapshotLabel)
        )
        UserDefaults.standard.set(source.rawValue, forKey: StorageKey.locationSource)
    }

    private func clearPersistedSnapshot() {
        hasUserSelectedLocation = false
        usesManualLocation = false
        locationSnapshot = nil
        UserDefaults.standard.removeObject(forKey: StorageKey.locationSource)
        UserDefaults.standard.removeObject(forKey: StorageKey.usesManualLocation)
        UserDefaults.standard.removeObject(forKey: StorageKey.manualQuery)
        UserDefaults.standard.removeObject(forKey: StorageKey.snapshotCountry)
        UserDefaults.standard.removeObject(forKey: StorageKey.snapshotSubdivision)
        UserDefaults.standard.removeObject(forKey: StorageKey.snapshotLabel)
    }
}

extension DashboardLocationService: CLLocationManagerDelegate {
    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard !usesManualLocation else { return }
            switch manager.authorizationStatus {
            case .authorized, .authorizedAlways:
                guard !hasUserSelectedLocation else { return }
                requestDeviceLocation()
            case .denied, .restricted:
                pendingLocationRequest = false
                isResolving = false
                applyFallbackRegionIfNeeded()
            default:
                break
            }
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            pendingLocationRequest = false
            isResolving = false
            guard !usesManualLocation else { return }
            await resolveDeviceLocation(location)
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            pendingLocationRequest = false
            isResolving = false
            guard !usesManualLocation else { return }
            applyFallbackRegionIfNeeded()
            statusMessage = nil
        }
    }
}

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
