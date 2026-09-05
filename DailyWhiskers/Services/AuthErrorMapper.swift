import FirebaseAuth
import Foundation

enum AuthErrorMapper {
    enum Context {
        case authentication, passwordReset, logout
    }

    static let resetConfirmation = "If an account exists for this email, you'll receive a reset link."

    static func message(for error: Error, context: Context = .authentication) -> String {
        let nsError = error as NSError
        let fallback: String
        switch context {
        case .authentication: fallback = "Something went wrong. Please try again."
        case .passwordReset: fallback = "Couldn't send a reset link. Please try again."
        case .logout: fallback = "Couldn't log out. Please try again."
        }
        guard nsError.domain == AuthErrorDomain,
              let code = AuthErrorCode(rawValue: nsError.code) else { return fallback }

        if context == .passwordReset, code == .invalidEmail {
            return "Enter a valid email address."
        }
        if context == .logout { return fallback }

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
