import Foundation
import LocalAuthentication

@MainActor
final class MobileDeviceLockService: ObservableObject {
    static let shared = MobileDeviceLockService()

    private enum StorageKey {
        static let requireBiometrics = "nucleus.mobile.security.requireBiometrics"
        static let requirePasscode = "nucleus.mobile.security.requirePasscode"
    }

    @Published var requireBiometrics: Bool {
        didSet {
            guard requireBiometrics != oldValue else { return }
            UserDefaults.standard.set(requireBiometrics, forKey: StorageKey.requireBiometrics)
            enforceAtLeastOneRequirement(prefer: .biometrics)
            syncLockStateForProtectionChange()
        }
    }

    @Published var requirePasscode: Bool {
        didSet {
            guard requirePasscode != oldValue else { return }
            UserDefaults.standard.set(requirePasscode, forKey: StorageKey.requirePasscode)
            enforceAtLeastOneRequirement(prefer: .passcode)
            syncLockStateForProtectionChange()
        }
    }

    @Published private(set) var isLocked = true
    @Published private(set) var canAuthenticate = false
    @Published var lastErrorMessage: String?

    private(set) var biometryType: LABiometryType = .none

    var isProtectionEnabled: Bool {
        requireBiometrics || requirePasscode
    }

    var biometricSettingLabel: String {
        "Require biometric unlock"
    }

    var unlockMethodLabel: String {
        if requireBiometrics, biometryType != .none {
            return "Biometrics"
        }
        return "Device passcode"
    }

    var unlockButtonTitle: String {
        if requireBiometrics, biometryType != .none {
            if requirePasscode {
                return "Unlock with \(unlockMethodLabel)"
            }
            return "Unlock with \(unlockMethodLabel)"
        }
        return "Unlock with passcode"
    }

    private init() {
        let defaults = UserDefaults.standard
        if ProcessInfo.processInfo.arguments.contains("-screenshotMode") {
            requireBiometrics = false
            requirePasscode = false
        } else if defaults.object(forKey: StorageKey.requireBiometrics) != nil {
            requireBiometrics = defaults.bool(forKey: StorageKey.requireBiometrics)
            requirePasscode = defaults.bool(forKey: StorageKey.requirePasscode)
        } else {
            requireBiometrics = true
            requirePasscode = true
        }
        refreshAvailability()
        syncLockStateForProtectionChange()
    }

    func refreshAvailability() {
        let context = LAContext()
        var error: NSError?
        canAuthenticate = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        biometryType = context.biometryType

        if isProtectionEnabled, !canAuthenticate {
            lastErrorMessage = unavailableMessage(for: error)
        } else {
            lastErrorMessage = nil
        }
    }

    func lock() {
        guard isProtectionEnabled else {
            isLocked = false
            return
        }
        isLocked = true
    }

    @discardableResult
    func unlock() async -> Bool {
        guard isProtectionEnabled else {
            isLocked = false
            return true
        }

        refreshAvailability()
        guard canAuthenticate else { return false }

        let context = LAContext()
        context.localizedFallbackTitle = requirePasscode ? "Enter Passcode" : ""
        context.localizedCancelTitle = "Cancel"

        let policy = authenticationPolicy

        do {
            let success = try await context.evaluatePolicy(
                policy,
                localizedReason: unlockReason
            )
            if success {
                isLocked = false
                lastErrorMessage = nil
            }
            return success
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .systemCancel, .appCancel:
                break
            case .authenticationFailed:
                lastErrorMessage = authenticationFailedMessage
            case .biometryLockout:
                lastErrorMessage = "\(unlockMethodLabel) is locked. Use your device passcode to unlock Nucleus."
            default:
                lastErrorMessage = error.localizedDescription
            }
            return false
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    private var authenticationPolicy: LAPolicy {
        if requireBiometrics, biometryType != .none, !requirePasscode {
            return .deviceOwnerAuthenticationWithBiometrics
        }
        return .deviceOwnerAuthentication
    }

    private var unlockReason: String {
        if requireBiometrics, biometryType != .none, requirePasscode {
            return "Unlock Nucleus with \(unlockMethodLabel) or your device passcode."
        }
        if requireBiometrics, biometryType != .none {
            return "Unlock Nucleus with \(unlockMethodLabel)."
        }
        return "Unlock Nucleus with your device passcode."
    }

    private var authenticationFailedMessage: String {
        if requireBiometrics, biometryType != .none, requirePasscode {
            return "Authentication failed. Try again with \(unlockMethodLabel.lowercased()) or your device passcode."
        }
        if requirePasscode {
            return "Authentication failed. Try your device passcode again."
        }
        return "Authentication failed. Try again."
    }

    private enum PreferredRequirement {
        case biometrics
        case passcode
    }

    private func enforceAtLeastOneRequirement(prefer: PreferredRequirement) {
        guard !requireBiometrics, !requirePasscode else { return }

        switch prefer {
        case .biometrics:
            requirePasscode = true
        case .passcode:
            requireBiometrics = true
        }
    }

    private func syncLockStateForProtectionChange() {
        if isProtectionEnabled {
            if !canAuthenticate {
                refreshAvailability()
            }
        } else {
            isLocked = false
            lastErrorMessage = nil
        }
    }

    private func unavailableMessage(for error: NSError?) -> String {
        guard let error else {
            return "Set a device passcode in Settings to protect Nucleus."
        }

        switch LAError.Code(rawValue: error.code) {
        case .passcodeNotSet:
            return "Set a device passcode in Settings to use Nucleus."
        case .biometryNotAvailable:
            return "Device authentication is unavailable. Set a passcode in Settings to use Nucleus."
        case .biometryNotEnrolled:
            return "Set up biometric unlock or a device passcode in Settings to use Nucleus."
        default:
            return error.localizedDescription
        }
    }
}
