import NucleusCore
import SwiftUI

public struct DashboardWeatherCard: View {
    let weather: DashboardTodayWeather?
    let isLoading: Bool
    let statusMessage: String?
    let locationPrompt: DashboardWeatherLocationPrompt?
    let onLocationAction: (DashboardWeatherLocationPrompt.Action) -> Void
    var onRetry: (() -> Void)?

    public init(
        weather: DashboardTodayWeather?,
        isLoading: Bool,
        statusMessage: String?,
        locationPrompt: DashboardWeatherLocationPrompt?,
        onLocationAction: @escaping (DashboardWeatherLocationPrompt.Action) -> Void,
        onRetry: (() -> Void)? = nil
    ) {
        self.weather = weather
        self.isLoading = isLoading
        self.statusMessage = statusMessage
        self.locationPrompt = locationPrompt
        self.onLocationAction = onLocationAction
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
                    Text(statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let onRetry {
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
                    title: "iCloud",
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
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isConnected ? "checkmark.circle.fill" : systemImage)
                .foregroundStyle(isConnected ? .green : .secondary)
                .frame(width: 18)

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
    let countryGroups: [DashboardPublicHolidayCountryGroup]
    let isLoading: Bool
    let statusMessage: String?

    public init(
        countryGroups: [DashboardPublicHolidayCountryGroup],
        isLoading: Bool,
        statusMessage: String?
    ) {
        self.countryGroups = countryGroups
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
            self.countryGroups = [
                DashboardPublicHolidayCountryGroup(
                    countryCode: holiday.countryCode,
                    countryName: DashboardPublicHolidayCountryCatalog.localizedCountryName(for: holiday.countryCode),
                    locationLabel: locationLabel,
                    holidays: [holiday]
                ),
            ]
        } else {
            self.countryGroups = []
        }
        self.isLoading = isLoading
        self.statusMessage = statusMessage
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(publicHolidayTitle, systemImage: "calendar.badge.clock")
                .font(.headline)
                .symbolRenderingMode(.multicolor)

            if !countryGroups.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(countryGroups) { group in
                        countryColumn(group)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
        if countryGroups.isEmpty {
            return "Public holidays"
        }
        if countryGroups.count == 1 {
            return "Public holidays · \(countryGroups[0].countryName)"
        }
        return "Public holidays · \(countryGroups.map(\.countryName).joined(separator: " · "))"
    }

    @ViewBuilder
    private func countryColumn(_ group: DashboardPublicHolidayCountryGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let locationLabel = group.locationLabel {
                Text("\(group.countryName) · \(locationLabel)")
                    .font(.subheadline.weight(.semibold))
            } else {
                Text(group.countryName)
                    .font(.subheadline.weight(.semibold))
            }

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
                Text("\(holiday.relativeDescription) · \(formattedHolidayDate(holiday.date))")
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
