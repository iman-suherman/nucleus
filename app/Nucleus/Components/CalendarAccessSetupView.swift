import AppKit
import CalendarKit
import SwiftUI

struct CalendarAccessSetupView: View {
    @ObservedObject private var calendarService = MacCalendarSyncService.shared
    @State private var isSettingUp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .foregroundStyle(Color.accentColor)
                Text("Calendar Access")
                    .font(.headline)
                Spacer()
                if calendarService.accessState == .authorized {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }

            Text("Nucleus reads your macOS Calendar schedule to show upcoming events on the Dashboard and send meeting reminders with video call links.")
                .font(.caption)
                .foregroundStyle(.secondary)

            permissionRow

            HStack(spacing: 10) {
                Button {
                    Task { await runSetup() }
                } label: {
                    if isSettingUp {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    } else {
                        Text(calendarService.accessState == .authorized ? "Refresh Schedule" : "Allow Calendar Access")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSettingUp)

                if calendarService.accessState != .authorized {
                    Button("Open Settings") {
                        calendarService.openCalendarAccessSettings()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let error = calendarService.lastSyncError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(calendarService.accessState == .authorized ? 0 : 0.25), lineWidth: 1)
        )
        .onAppear {
            calendarService.refreshAccessState()
        }
    }

    private var permissionRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: calendarService.accessState == .authorized ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(calendarService.accessState == .authorized ? .green : .secondary)
                .font(.body)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text("Full Calendar Access")
                    .font(.subheadline.weight(.semibold))
                Text("Includes Google, iCloud, Exchange, and other calendars synced to the Calendar app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(statusLabel)
                    .font(.caption2)
                    .foregroundStyle(calendarService.accessState == .authorized ? .secondary : Color.orange)
            }

            Spacer(minLength: 8)

            if calendarService.accessState != .authorized {
                Button("Fix") {
                    if calendarService.accessState == .denied || calendarService.accessState == .restricted {
                        calendarService.openCalendarAccessSettings()
                    } else {
                        Task { await runSetup() }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var statusLabel: String {
        switch calendarService.accessState {
        case .authorized:
            return "Allowed"
        case .notDetermined:
            return "Not requested yet"
        case .denied:
            return "Denied — enable Nucleus in System Settings → Calendars"
        case .restricted:
            return "Restricted on this Mac"
        }
    }

    private func runSetup() async {
        isSettingUp = true
        defer { isSettingUp = false }
        await calendarService.requestAccessAndSync()
    }
}
