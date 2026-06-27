import NucleusCore
import NucleusUI
import SwiftUI

struct MobileRootView: View {
    @EnvironmentObject private var viewModel: MobileAppViewModel
    @EnvironmentObject private var deviceLock: MobileDeviceLockService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Group {
                if viewModel.isBootstrapping {
                    ProgressView(viewModel.statusMessage)
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
        }
        .animation(.easeInOut(duration: 0.22), value: viewModel.showWhatsNew)
        .animation(.easeInOut(duration: 0.2), value: deviceLock.isLocked)
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
