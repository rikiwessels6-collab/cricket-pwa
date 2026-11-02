import Foundation
import LocalAuthentication
import Observation
import SteadyCore

/// Locks the app after it has been in the background for the chosen time and
/// unlocks it with Face ID / Touch ID, falling back to the device passcode.
/// The app never sees or stores face data: LocalAuthentication only reports
/// whether the phone's owner authenticated.
@Observable
@MainActor
final class AppLock {
    private(set) var isLocked = false
    var lastError: String?
    private(set) var enabled = false
    private var policy = LockPolicy(timeout: 60)
    private var backgroundedAt: Date?

    /// UI tests pass -UITestBypassAuth so the lock can be exercised without a face.
    private var bypass: Bool { ProcessInfo.processInfo.arguments.contains("-UITestBypassAuth") }

    func configure(enabled: Bool, timeoutSeconds: Int) {
        self.enabled = enabled
        policy = LockPolicy(timeout: TimeInterval(timeoutSeconds))
        if !enabled { isLocked = false }
    }

    func lockNow() {
        if enabled { isLocked = true }
    }

    func didEnterBackground() {
        backgroundedAt = .now
    }

    func willEnterForeground() {
        if enabled, policy.shouldLock(backgroundedAt: backgroundedAt, now: .now) { isLocked = true }
        backgroundedAt = nil
    }

    func unlock() async {
        lastError = nil
        if bypass { isLocked = false; return }
        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode set on the phone: there is nothing to check against.
            lastError = "Set a passcode on this iPhone to protect Steady Strength."
            isLocked = false
            return
        }
        do {
            if try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your health data") {
                isLocked = false
            }
        } catch {
            lastError = (error as? LAError)?.code == .userCancel ? nil : error.localizedDescription
        }
    }

    /// "Face ID", "Touch ID", "Optic ID" or "Passcode", for button labels.
    static var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    static var biometrySymbol: String {
        switch biometryName {
        case "Face ID": return "faceid"
        case "Touch ID": return "touchid"
        case "Optic ID": return "opticid"
        default: return "lock"
        }
    }
}
