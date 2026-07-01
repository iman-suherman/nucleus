import NucleusCore
import NucleusUI
import SwiftUI

struct MobileRootView: View {
    @EnvironmentObject private var viewModel: MobileAppViewModel
    @EnvironmentObject private var deviceLock: MobileDeviceLockService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase

    private var showsBootstrapBlockingUI: Bool {
        viewModel.isBootstrapping
            && (!deviceLock.isProtectionEnabled || !deviceLock.isLocked)
    }

    var body: some View {
        ZStack {
            Group {
                if showsBootstrapBlockingUI {
                    MobileBootstrapSyncView(
                        stage: viewModel.bootstrapStage,
                        detailMessage: viewModel.bootstrapDetailMessage
                    )
                } else if horizontalSizeClass == .regular {
                    TabletRootView()
                } else {
                    PhoneRootView()
                }
            }
            .tint(NucleusMobileTheme.accent)
            .alert("Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }

            if deviceLock.isProtectionEnabled, deviceLock.isLocked {
                MobileDeviceLockScreen()
                    .transition(.opacity)
            }

            if viewModel.showWhatsNew, let release = viewModel.whatsNewRelease {
                WhatsNewOverlay(release: release) {
                    viewModel.dismissWhatsNew()
                }
            }

            if let prompt = viewModel.meetingReminders.prompt {
                DashboardMeetingReminderOverlay(
                    prompt: prompt,
                    onJoinMeeting: { event in
                        viewModel.joinMeetingFromReminder(event)
                    },
                    onOpenCalendar: {
                        viewModel.openCalendarFromMeetingReminder()
                    },
                    onDismiss: {
                        viewModel.dismissMeetingReminder()
                    }
                )
            }
        }
        .animation(.easeInOut(duration: 0.22), value: viewModel.showWhatsNew)
        .animation(.easeInOut(duration: 0.2), value: deviceLock.isLocked)
        .animation(.easeInOut(duration: 0.2), value: viewModel.meetingReminders.prompt != nil)
        .sheet(isPresented: $viewModel.showsSettings) {
            SettingsWorkspaceScreen()
        }
        .task {
            viewModel.beginStartup()
        }
        .task {
            guard deviceLock.isProtectionEnabled, deviceLock.isLocked else { return }
            await deviceLock.unlock()
        }
        .onChange(of: scenePhase) { _, phase in
            guard deviceLock.isProtectionEnabled else { return }

            switch phase {
            case .active:
                guard deviceLock.isLocked else { return }
                Task { await deviceLock.unlock() }
            case .background:
                deviceLock.lock()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }
}
