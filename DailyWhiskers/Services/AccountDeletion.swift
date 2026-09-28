import Foundation

enum AccountDeletionError: Error {
    case passwordRequired
    case sessionChanged
}

@MainActor
enum AccountDeletion {
    static func perform(
        password: String,
        reauthenticate: (String) async throws -> Void,
        delete: () async throws -> Void
    ) async throws {
        guard !password.isEmpty else { throw AccountDeletionError.passwordRequired }
        try Task.checkCancellation()
        try await reauthenticate(password)
        // Never issue a destructive request after cancelled reauthentication.
        try Task.checkCancellation()
        try await delete()
    }
}
