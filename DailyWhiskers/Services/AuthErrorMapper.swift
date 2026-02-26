import FirebaseAuth
import Foundation

enum AuthErrorMapper {
    static func message(for error: Error) -> String {
        let nsError = error as NSError
        guard let code = AuthErrorCode(rawValue: nsError.code) else {
            return "Something went wrong. Please try again."
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
        default:
            return "Something went wrong. Please try again."
        }
    }
}
