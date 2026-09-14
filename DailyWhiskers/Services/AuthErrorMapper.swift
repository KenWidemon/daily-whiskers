import FirebaseAuth
import Foundation

enum AuthErrorMapper {
    enum Context {
        case authentication, passwordReset, logout, accountDeletion
    }

    static let resetConfirmation = "If an account exists for this email, you'll receive a reset link."

    static func message(for error: Error, context: Context = .authentication) -> String {
        if context == .accountDeletion, let deletionError = error as? AccountDeletionError {
            switch deletionError {
            case .passwordRequired: return "Enter your current password to delete your account."
            case .sessionChanged: return "Your session changed. Sign in again before deleting your account."
            }
        }
        let nsError = error as NSError
        let fallback: String
        switch context {
        case .authentication: fallback = "Something went wrong. Please try again."
        case .passwordReset: fallback = "Couldn't send a reset link. Please try again."
        case .logout: fallback = "Couldn't log out. Please try again."
        case .accountDeletion: fallback = "Couldn't delete your account. Please try again."
        }
        guard nsError.domain == AuthErrorDomain,
              let code = AuthErrorCode(rawValue: nsError.code) else { return fallback }

        if context == .passwordReset, code == .invalidEmail {
            return "Enter a valid email address."
        }
        if context == .logout { return fallback }

        if context == .accountDeletion {
            switch code {
            case .requiresRecentLogin, .invalidCredential, .wrongPassword:
                return "Couldn't verify your password. Enter your current password and try again."
            case .userNotFound, .userTokenExpired, .invalidUserToken, .userDisabled:
                return "Your account session is no longer valid. Sign in again to continue."
            case .keychainError:
                return "Account deletion or local sign-out could not finish. Restart the app and check your account before retrying."
            default: break
            }
        }

        switch code {
        case .invalidCredential, .wrongPassword, .userNotFound, .invalidEmail:
            return "Invalid email or password."
        case .emailAlreadyInUse:
            return "An account already exists for that email."
        case .weakPassword:
            return "Password is too weak. Use at least 6 characters."
        case .networkError:
            return "Network error. Check your connection and try again."
        case .tooManyRequests:
            return "Too many attempts. Please wait a moment and try again."
        case .keychainError:
            return "Couldn't access secure account storage. Restart the app and try again."
        default:
            return fallback
        }
    }
}
