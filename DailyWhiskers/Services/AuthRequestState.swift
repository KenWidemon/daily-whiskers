import FirebaseAuth
import Foundation
import Combine
import os

@MainActor
final class AuthRequestState: ObservableObject {
#if DEBUG
    private static let logger = Logger(subsystem: "DailyWhiskers", category: "AuthRecovery")
#endif
    enum Operation {
        case signIn, createAccount, testAccount, passwordReset, logout

        var announcement: String {
            switch self {
            case .signIn, .testAccount: return "Signing in."
            case .createAccount: return "Creating account."
            case .passwordReset: return "Sending reset link."
            case .logout: return "Logging out."
            }
        }
    }

    @Published private(set) var operation: Operation?
    @Published var errorMessage: String?
    @Published var confirmation: String?

    var isWorking: Bool { operation != nil }

    static func normalizedEmail(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isValidEmail(_ value: String) -> Bool {
        let pattern = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return normalizedEmail(value).range(of: pattern, options: .regularExpression) != nil
    }

    func clearFeedback() {
        errorMessage = nil
        confirmation = nil
    }

    func resetPassword(email: String, send: (String) async throws -> Void) async {
        guard !isWorking else { return }
        guard Self.isValidEmail(email) else {
            clearFeedback()
            errorMessage = "Enter a valid email address."
            return
        }
        await perform(.passwordReset) {
            try await send(Self.normalizedEmail(email))
        }
    }

    func perform(_ requestedOperation: Operation, action: () async throws -> Void) async {
        guard !isWorking else { return }
        operation = requestedOperation
        clearFeedback()
        defer { operation = nil }

        do {
            try await action()
            if requestedOperation == .passwordReset {
                confirmation = AuthErrorMapper.resetConfirmation
            }
        } catch is CancellationError {
            // Cancellation releases the request lock without presenting an error.
        } catch {
            let nsError = error as NSError
#if DEBUG
            // Never log descriptions or userInfo: they can contain credentials or account data.
            Self.logger.error("Auth operation \(String(describing: requestedOperation), privacy: .public) failed: domain=\(nsError.domain, privacy: .public) code=\(nsError.code)")
            if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                Self.logger.error("Underlying auth error: domain=\(underlying.domain, privacy: .public) code=\(underlying.code)")
            }
#endif
            if requestedOperation == .passwordReset,
               nsError.domain == AuthErrorDomain,
               nsError.code == AuthErrorCode.userNotFound.rawValue {
                confirmation = AuthErrorMapper.resetConfirmation
                return
            }
            let context: AuthErrorMapper.Context
            switch requestedOperation {
            case .passwordReset: context = .passwordReset
            case .logout: context = .logout
            default: context = .authentication
            }
            errorMessage = AuthErrorMapper.message(for: error, context: context)
        }
    }
}
