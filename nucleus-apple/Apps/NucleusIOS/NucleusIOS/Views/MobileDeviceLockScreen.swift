import LocalAuthentication
import NucleusUI
import SwiftUI

struct MobileDeviceLockScreen: View {
    @EnvironmentObject private var deviceLock: MobileDeviceLockService
    @State private var isUnlocking = false

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: lockIconName)
                    .font(.system(size: 52))
                    .foregroundStyle(NucleusMobileTheme.accent)
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: 8) {
                    Text("Nucleus is locked")
                        .font(.title2.bold())

                    Text(unlockDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                if let message = deviceLock.lastErrorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
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
                    .padding(.horizontal, 32)
                } else {
                    Text("Open device Settings → Passcode & security to enable biometric unlock, then return to Nucleus.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    Button("Check again") {
                        deviceLock.refreshAvailability()
                        Task { await attemptUnlock() }
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal, 32)
                }
            }
        }
        .task {
            guard deviceLock.isProtectionEnabled else { return }
            await attemptUnlock()
        }
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
