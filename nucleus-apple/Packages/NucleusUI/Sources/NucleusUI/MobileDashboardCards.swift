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
                Label("Today's weather · \(cityName)", systemImage: "cloud.sun.fill")
                    .font(.headline)
                    .symbolRenderingMode(.multicolor)
            } else {
                Label("Today's weather", systemImage: "cloud.sun.fill")
                    .font(.headline)
                    .symbolRenderingMode(.multicolor)
            }

            if let prompt = locationPrompt {
                locationPromptCard(prompt)
            } else if let weather {
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
    let holiday: DashboardNextPublicHoliday?
    let locationLabel: String?
    let isLoading: Bool
    let statusMessage: String?

    public init(
        holiday: DashboardNextPublicHoliday?,
        locationLabel: String? = nil,
        isLoading: Bool,
        statusMessage: String?
    ) {
        self.holiday = holiday
        self.locationLabel = locationLabel
        self.isLoading = isLoading
        self.statusMessage = statusMessage
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let holiday {
                Label(
                    "Next public holiday · \(locationLabel ?? Locale.current.localizedString(forRegionCode: holiday.countryCode) ?? holiday.countryCode)",
                    systemImage: "calendar.badge.clock"
                )
                .font(.headline)
                .symbolRenderingMode(.multicolor)
            } else {
                Label("Next public holiday", systemImage: "calendar.badge.clock")
                    .font(.headline)
                    .symbolRenderingMode(.multicolor)
            }

            if let holiday {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "flag.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(holiday.name)
                            .font(.subheadline.weight(.semibold))
                        Text("\(holiday.relativeDescription) · \(formattedHolidayDate(holiday.date))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
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

    private func formattedHolidayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
