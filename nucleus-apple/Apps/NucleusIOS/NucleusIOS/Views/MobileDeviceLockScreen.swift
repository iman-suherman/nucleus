import LocalAuthentication
import NucleusCore
import NucleusUI
import SwiftUI

struct MobileDeviceLockScreen: View {
    @EnvironmentObject private var deviceLock: MobileDeviceLockService
    @State private var isUnlocking = false

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        NucleusMobileSplashBranding()

                        Text(NucleusAppBranding.mobileCompanionSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 360)
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 40)
                    .padding(.bottom, 24)
                }

                unlockPanel
            }
        }
    }

    private var unlockPanel: some View {
        VStack(spacing: 16) {
            Divider()

            Image(systemName: lockIconName)
                .font(.system(size: 28))
                .foregroundStyle(NucleusMobileTheme.accent)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 6) {
                Text("Nucleus is locked")
                    .font(.headline)

                Text(unlockDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let message = deviceLock.lastErrorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            if deviceLock.canAuthenticate {
                Button {
                    Task { await attemptUnlock() }
                } label: {
                    if isUnlocking {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(deviceLock.unlockButtonTitle)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(NucleusMobileTheme.accent)
                .disabled(isUnlocking)
            } else {
                Text("Open device Settings → Passcode & security to enable biometric unlock, then return to Nucleus.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Check again") {
                    deviceLock.refreshAvailability()
                    Task { await attemptUnlock() }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 16)
        .padding(.bottom, 28)
        .background(.bar)
    }

    private var unlockDescription: String {
        if deviceLock.requireBiometrics, deviceLock.biometryType != .none, deviceLock.requirePasscode {
            return "Use \(deviceLock.unlockMethodLabel) or your device passcode to continue."
        }
        if deviceLock.requirePasscode {
            return "Use your device passcode to continue."
        }
        return "Use \(deviceLock.unlockMethodLabel) to continue."
    }

    private var lockIconName: String {
        switch deviceLock.biometryType {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        default:
            return "lock.shield.fill"
        }
    }

    private func attemptUnlock() async {
        guard deviceLock.canAuthenticate, !isUnlocking else { return }
        isUnlocking = true
        defer { isUnlocking = false }
        await deviceLock.unlock()
    }
}
