#if DEBUG && CI_SMOKE_TESTING
import Foundation

// Compiled only by the dedicated CI Debug command, never the Release app.
// No fake successful authentication: unexpected backend calls fail closed.
enum CISmokeMode {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("--ci-smoke") }

    enum OfflineError: Error { case unexpectedAuthOperation }

    static func rejectAuthOperation() throws {
        if isEnabled { throw OfflineError.unexpectedAuthOperation }
    }
}
#endif
