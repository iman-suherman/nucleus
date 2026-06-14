import SwiftUI

enum StartupStep: String, CaseIterable, Identifiable {
    case database
    case accounts
    case clipboard
    case notifications
    case mailSync
    case calendarSync

    var id: String { rawValue }

    var title: String {
        switch self {
        case .database: return "Loading workspace data"
        case .accounts: return "Restoring Google accounts"
        case .clipboard: return "Starting clipboard monitor"
        case .notifications: return "Preparing notifications"
        case .mailSync: return "Syncing mail"
        case .calendarSync: return "Syncing calendar"
        }
    }

    var icon: String {
        switch self {
        case .database: return "externaldrive"
        case .accounts: return "person.crop.circle"
        case .clipboard: return "doc.on.clipboard"
        case .notifications: return "bell"
        case .mailSync: return "tray.full"
        case .calendarSync: return "calendar"
        }
    }
}

struct StartupSplashOverlay: View {
    let version: String
    let currentMessage: String
    let completedSteps: Set<StartupStep>
    let activeStep: StartupStep?
    let progressFraction: Double

    private var progressLabel: String {
        "\(Int((progressFraction * 100).rounded()))%"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
                   let image = NSImage(contentsOf: iconURL) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
                } else {
                    Image(systemName: "atom")
                        .font(.system(size: 44))
                        .foregroundStyle(.blue)
                        .frame(width: 88, height: 88)
                }

                VStack(spacing: 6) {
                    Text("Starting Nucleus")
                        .font(.title2.bold())
                    Text("Personal Operating System · v\(version)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(currentMessage)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                    .animation(.easeInOut(duration: 0.2), value: currentMessage)

                ProgressView(value: progressFraction)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 280)
                Text(progressLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(StartupStep.allCases) { step in
                        startupStepRow(step)
                    }
                }
                .frame(maxWidth: 320, alignment: .leading)
                .padding(.top, 4)
            }
            .padding(32)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 28, y: 14)
            .padding(40)
        }
        .transition(.opacity)
        .zIndex(100)
    }

    @ViewBuilder
    private func startupStepRow(_ step: StartupStep) -> some View {
        let isComplete = completedSteps.contains(step)
        let isActive = activeStep == step

        HStack(spacing: 10) {
            Group {
                if isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if isActive {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: step.icon)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 18)

            Text(step.title)
                .font(.subheadline)
                .foregroundStyle(isComplete || isActive ? .primary : .secondary)
        }
    }
}
