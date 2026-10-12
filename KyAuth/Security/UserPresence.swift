import Foundation
import LocalAuthentication

enum UserPresenceError: LocalizedError {
    case cancelled
    case noPasscode
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: "Authentication was cancelled."
        case .noPasscode: "KyAuth needs a device passcode. Set one in Settings, then try again."
        case .failed(let message): message
        }
    }
}

/// One Face ID, Touch ID or passcode check. The evaluated context unlocks exactly the Keychain item
/// or Secure Enclave key it is handed to, then is invalidated by the caller.
enum UserPresence {
    static var deviceHasPasscode: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

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

    static func evaluate(reason: String) async throws -> LAContext {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw UserPresenceError.noPasscode
        }
        do {
            _ = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return context
        } catch let error as LAError where [.userCancel, .appCancel, .systemCancel].contains(error.code) {
            throw UserPresenceError.cancelled
        } catch let error as LAError where error.code == .passcodeNotSet {
            throw UserPresenceError.noPasscode
        } catch {
            throw UserPresenceError.failed(error.localizedDescription)
        }
    }
}
