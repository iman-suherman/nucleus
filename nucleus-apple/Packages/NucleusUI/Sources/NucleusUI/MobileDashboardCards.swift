import Combine
import NucleusCore
import SwiftUI

public struct DashboardWeatherCard: View {
    let weather: DashboardTodayWeather?
    let isLoading: Bool
    let isAwaitingDeviceLocation: Bool
    let statusMessage: String?
    let locationPrompt: DashboardWeatherLocationPrompt?
    let showsManualLocationEntry: Bool
    @Binding var manualLocationDraft: String
    let onLocationAction: (DashboardWeatherLocationPrompt.Action) -> Void
    var onManualLocationSubmit: (() -> Void)?
    var onRetry: (() -> Void)?

    public init(
        weather: DashboardTodayWeather?,
        isLoading: Bool,
        isAwaitingDeviceLocation: Bool = false,
        statusMessage: String?,
        locationPrompt: DashboardWeatherLocationPrompt?,
        showsManualLocationEntry: Bool = false,
        manualLocationDraft: Binding<String> = .constant(""),
        onLocationAction: @escaping (DashboardWeatherLocationPrompt.Action) -> Void,
        onManualLocationSubmit: (() -> Void)? = nil,
        onRetry: (() -> Void)? = nil
    ) {
        self.weather = weather
        self.isLoading = isLoading
        self.isAwaitingDeviceLocation = isAwaitingDeviceLocation
        self.statusMessage = statusMessage
        self.locationPrompt = locationPrompt
        self.showsManualLocationEntry = showsManualLocationEntry
        self._manualLocationDraft = manualLocationDraft
        self.onLocationAction = onLocationAction
        self.onManualLocationSubmit = onManualLocationSubmit
        self.onRetry = onRetry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let weather, let cityName = weather.cityName {
                Label("Weather · \(cityName)", systemImage: "cloud.sun.fill")
                    .font(.headline)
                    .symbolRenderingMode(.multicolor)
            } else {
                Label("Weather", systemImage: "cloud.sun.fill")
                    .font(.headline)
                    .symbolRenderingMode(.multicolor)
            }

            if let prompt = locationPrompt {
                locationPromptCard(prompt)
            } else if let weather {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: weather.conditionSymbol)
                            .font(.system(size: 32))
                            .symbolRenderingMode(.multicolor)
                            .frame(width: 40)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(weather.conditionDescription)
                                .font(.title3.weight(.semibold))
                            Text("High \(weather.highTemperature) · Low \(weather.lowTemperature)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let rainSummary = weather.rainSummary {
                                Text(rainSummary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Spacer(minLength: 0)
                    }

                    if !weather.dailyForecast.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(weather.dailyForecast) { day in
                                    VStack(spacing: 6) {
                                        Text(day.dayLabel)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        Image(systemName: day.conditionSymbol)
                                            .font(.title3)
                                            .symbolRenderingMode(.multicolor)
                                        Text(day.highTemperature)
                                            .font(.caption.weight(.semibold))
                                        Text(day.lowTemperature)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(minWidth: 54)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 6)
                                    .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            } else if isAwaitingDeviceLocation {
                findingLocationRow
            } else if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading forecast…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            } else if let statusMessage {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 10) {
                        Text(statusMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if showsManualLocationEntry {
                            manualLocationEntryControls
                        }
                    }

                    if let onRetry, !isLoading {
                        Button("Try again", action: onRetry)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var findingLocationRow: some View {
        HStack(alignment: .center, spacing: 10) {
            ProgressView()
            Text(statusMessage ?? "Finding your location…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if showsManualLocationEntry {
                manualLocationEntryControls
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var manualLocationEntryControls: some View {
        HStack(spacing: 8) {
            TextField("City or postcode", text: $manualLocationDraft)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 140)
                .submitLabel(.go)
                .onSubmit {
                    onManualLocationSubmit?()
                }
            if let onManualLocationSubmit {
                Button("Use", action: onManualLocationSubmit)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private func locationPromptCard(_ prompt: DashboardWeatherLocationPrompt) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(prompt.message)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)

            Button(prompt.buttonTitle) {
                onLocationAction(prompt.action)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

public struct DashboardResourceUsageCard: View {
    let metrics: DashboardProcessMetrics?

    public init(metrics: DashboardProcessMetrics?) {
        self.metrics = metrics
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Resource usage", systemImage: "gauge.with.dots.needle.67percent")
                .font(.subheadline.weight(.semibold))

            VStack(spacing: 0) {
                metricRow(label: "CPU", value: metrics?.formattedCPU ?? "—")
                Divider()
                metricRow(label: "Memory", value: metrics?.formattedMemory ?? "—")
            }
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func metricRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.subheadline.weight(.semibold))
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public struct DashboardCloudSyncCard: View {
    let syncService: ICloudSyncDisplayService
    let notesService: NotesMetadataService
    var onRefresh: (() -> Void)?

    public init(
        syncService: ICloudSyncDisplayService,
        notesService: NotesMetadataService,
        onRefresh: (() -> Void)? = nil
    ) {
        self.syncService = syncService
        self.notesService = notesService
        self.onRefresh = onRefresh
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Cloud sync", systemImage: "icloud")
                .font(.subheadline.weight(.semibold))

            VStack(spacing: 0) {
                syncRow(
                    title: "Cloud sync",
                    systemImage: "icloud.fill",
                    isConnected: syncService.isSyncAvailable && notesService.usesCloudKitSync,
                    statusLabel: statusLabel
                )
            }
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

            if let onRefresh {
                Button("Refresh sync", action: onRefresh)
                    .font(.caption)
            }
        }
    }

    private var statusLabel: String {
        if syncService.isSyncAvailable, notesService.usesCloudKitSync {
            return syncService.statusLabel
        }
        if !notesService.usesCloudKitSync {
            return notesService.syncStatusMessage
        }
        return syncService.statusLabel
    }

    private func syncRow(
        title: String,
        systemImage: String,
        isConnected: Bool,
        statusLabel: String
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: isConnected ? "checkmark.circle.fill" : systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isConnected ? .green : .secondary)
                .frame(width: 22, height: 22, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(statusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let name = syncService.accountName {
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text("\(notesService.notes.count) notes on this device")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

public struct DashboardPublicHolidayCard: View {
    let layout: DashboardPublicHolidayDisplayLayout
    let isLoading: Bool
    let statusMessage: String?

    @State private var companionCountryIndex = 0

    public init(
        layout: DashboardPublicHolidayDisplayLayout,
        isLoading: Bool,
        statusMessage: String?
    ) {
        self.layout = layout
        self.isLoading = isLoading
        self.statusMessage = statusMessage
    }

    public init(
        countryGroups: [DashboardPublicHolidayCountryGroup],
        isLoading: Bool,
        statusMessage: String?
    ) {
        self.layout = DashboardPublicHolidayDisplayLayout(
            location: countryGroups.first,
            companions: Array(countryGroups.dropFirst())
        )
        self.isLoading = isLoading
        self.statusMessage = statusMessage
    }

    public init(
        holiday: DashboardNextPublicHoliday?,
        locationLabel: String? = nil,
        isLoading: Bool,
        statusMessage: String?
    ) {
        if let holiday {
            self.layout = DashboardPublicHolidayDisplayLayout(
                location: DashboardPublicHolidayCountryGroup(
                    countryCode: holiday.countryCode,
                    countryName: DashboardPublicHolidayCountryCatalog.localizedCountryName(for: holiday.countryCode),
                    locationLabel: locationLabel,
                    holidays: [holiday]
                ),
                companions: []
            )
        } else {
            self.layout = DashboardPublicHolidayDisplayLayout(location: nil, companions: [])
        }
        self.isLoading = isLoading
        self.statusMessage = statusMessage
    }

    public var body: some View {
        let companions = layout.companions
        let companionIndex = companions.isEmpty ? 0 : companionCountryIndex % companions.count
        let activeCompanion = companions.isEmpty ? nil : companions[companionIndex]

        VStack(alignment: .leading, spacing: 10) {
            Label(publicHolidayTitle, systemImage: "calendar.badge.clock")
                .font(.headline)
                .symbolRenderingMode(.multicolor)

            if layout.location != nil || activeCompanion != nil {
                if let location = layout.location,
                   let activeCompanion,
                   !location.holidays.isEmpty,
                   !activeCompanion.holidays.isEmpty {
                    publicHolidayPairedRows(
                        location: location,
                        companion: activeCompanion,
                        companions: companions,
                        companionIndex: companionIndex
                    )
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        if let location = layout.location {
                            countryColumn(location, subtitle: "Your location")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let activeCompanion {
                            countryColumn(
                                activeCompanion,
                                subtitle: companions.count > 1
                                    ? "Selected country \(companionIndex + 1) of \(companions.count)"
                                    : "Selected country",
                                showsCompanionControls: companions.count > 1,
                                onPrevious: {
                                    guard companions.count > 1 else { return }
                                    companionCountryIndex = (companionIndex - 1 + companions.count) % companions.count
                                },
                                onNext: {
                                    guard companions.count > 1 else { return }
                                    companionCountryIndex = (companionIndex + 1) % companions.count
                                }
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .onReceive(Timer.publish(every: 8, on: .main, in: .common).autoconnect()) { _ in
                        guard companions.count > 1 else { return }
                        companionCountryIndex = (companionIndex + 1) % companions.count
                    }
                }
            } else if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading public holidays…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            } else if let statusMessage {
                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var publicHolidayTitle: String {
        layout.sectionTitle
    }

    private func publicHolidayPairedRows(
        location: DashboardPublicHolidayCountryGroup,
        companion: DashboardPublicHolidayCountryGroup,
        companions: [DashboardPublicHolidayCountryGroup],
        companionIndex: Int
    ) -> some View {
        let rowCount = max(location.holidays.count, companion.holidays.count)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                countryColumnHeader(location, subtitle: "Your location")
                    .frame(maxWidth: .infinity, alignment: .leading)

                countryColumnHeader(
                    companion,
                    subtitle: companions.count > 1
                        ? "Selected country \(companionIndex + 1) of \(companions.count)"
                        : "Selected country",
                    showsCompanionControls: companions.count > 1,
                    onPrevious: {
                        guard companions.count > 1 else { return }
                        companionCountryIndex = (companionIndex - 1 + companions.count) % companions.count
                    },
                    onNext: {
                        guard companions.count > 1 else { return }
                        companionCountryIndex = (companionIndex + 1) % companions.count
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            ForEach(0..<rowCount, id: \.self) { index in
                HStack(alignment: .top, spacing: 12) {
                    holidayRowSlot(
                        holiday: index < location.holidays.count ? location.holidays[index] : nil,
                        accentIndex: index
                    )
                    holidayRowSlot(
                        holiday: index < companion.holidays.count ? companion.holidays[index] : nil,
                        accentIndex: index
                    )
                }
            }
        }
        .onReceive(Timer.publish(every: 8, on: .main, in: .common).autoconnect()) { _ in
            guard companions.count > 1 else { return }
            companionCountryIndex = (companionIndex + 1) % companions.count
        }
    }

    @ViewBuilder
    private func holidayRowSlot(holiday: DashboardNextPublicHoliday?, accentIndex: Int) -> some View {
        Group {
            if let holiday {
                holidayRow(holiday, accentIndex: accentIndex)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func countryColumnHeader(
        _ group: DashboardPublicHolidayCountryGroup,
        subtitle: String,
        showsCompanionControls: Bool = false,
        onPrevious: (() -> Void)? = nil,
        onNext: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let locationLabel = group.locationLabel {
                    Text("\(group.countryName) · \(locationLabel)")
                        .font(.subheadline.weight(.semibold))
                } else {
                    Text(group.countryName)
                        .font(.subheadline.weight(.semibold))
                }
            }

            Spacer(minLength: 0)

            if showsCompanionControls {
                HStack(spacing: 8) {
                    Button(action: { onPrevious?() }) {
                        Image(systemName: "chevron.left")
                    }
                    Button(action: { onNext?() }) {
                        Image(systemName: "chevron.right")
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func countryColumn(
        _ group: DashboardPublicHolidayCountryGroup,
        subtitle: String,
        showsCompanionControls: Bool = false,
        onPrevious: (() -> Void)? = nil,
        onNext: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            countryColumnHeader(
                group,
                subtitle: subtitle,
                showsCompanionControls: showsCompanionControls,
                onPrevious: onPrevious,
                onNext: onNext
            )

            if group.holidays.isEmpty {
                Text("No upcoming public holidays.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(Array(group.holidays.enumerated()), id: \.offset) { index, holiday in
                    holidayRow(holiday, accentIndex: index)
                }
            }
        }
    }

    private func holidayRow(_ holiday: DashboardNextPublicHoliday, accentIndex: Int) -> some View {
        let accent = holidayAccentColor(for: holiday, index: accentIndex)

        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: "calendar")
                .font(.title3)
                .foregroundStyle(accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(holiday.name)
                    .font(.subheadline.weight(.semibold))
                Text("\(holiday.relativeDescription) · \(formattedHolidayDate(holiday.date)) · \(holiday.weekdayName) · \(holiday.dayKindLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(holiday.scopeLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(accent)
                if let applicabilityLabel = holiday.applicabilityLabel {
                    Text(applicabilityLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private func holidayAccentColor(for holiday: DashboardNextPublicHoliday, index: Int) -> Color {
        let palette: [Color] = [
            Color(red: 0.95, green: 0.45, blue: 0.18),
            Color(red: 0.55, green: 0.36, blue: 0.92),
            Color(red: 0.18, green: 0.66, blue: 0.72),
            Color(red: 0.92, green: 0.32, blue: 0.52),
            Color(red: 0.24, green: 0.62, blue: 0.38),
            Color(red: 0.86, green: 0.58, blue: 0.16),
            Color(red: 0.34, green: 0.48, blue: 0.92),
        ]
        let key = abs(holiday.name.hashValue ^ holiday.countryCode.hashValue ^ index)
        return palette[key % palette.count]
    }

    private func formattedHolidayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
