#if DEBUG && CI_SMOKE_TESTING
import Foundation
import UIKit

// Compiled only by the dedicated CI Debug command, never the Release app.
// No fake successful authentication: unexpected backend calls fail closed.
enum CISmokeMode {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("--ci-smoke") }

    private static var shareAttempt = 0
    static func failShareIfRequested() throws {
        guard isEnabled, ProcessInfo.processInfo.arguments.contains("--ci-smoke-share-failure-once") else { return }
        shareAttempt += 1
        if shareAttempt == 1 { throw DailyCardShareError.renderingFailed }
    }

    // Opt-in simulator evidence of the exact payload handed to UIActivityViewController.
    // Absent from normal Debug/Release builds; no production export files are created.
    static func recordSharePayload(_ export: DailyCardShareExport) {
        guard isEnabled, ProcessInfo.processInfo.arguments.contains("--ci-smoke-export-evidence") else { return }
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShareEvidence", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let stem = UUID().uuidString
            try export.image.pngData()?.write(to: folder.appendingPathComponent(stem + ".png"))
            try export.text.write(to: folder.appendingPathComponent(stem + ".txt"), atomically: true, encoding: .utf8)
        } catch { assertionFailure("Unable to retain opted-in local share evidence") }
    }

    enum OfflineError: Error { case unexpectedAuthOperation }

    static func rejectAuthOperation() throws {
        if isEnabled { throw OfflineError.unexpectedAuthOperation }
    }
}
#endif

#if DEBUG && CI_SMOKE_TESTING && SAVED_TIMING_DIAGNOSTIC
import os

// Temporary diagnostic branch only: static event names and synthetic-state flags.
enum SavedTimingDiagnostic {
    private static let logger = Logger(subsystem: "com.dailywhiskers.saved-timing", category: "diagnostic")
    static func mark(_ event: String, _ detail: String = "") {
        guard CISmokeMode.isEnabled else { return }
        logger.notice("DW_SAVE_TIMING uptime=\(ProcessInfo.processInfo.systemUptime, privacy: .public) event=\(event, privacy: .public) \(detail, privacy: .public)")
    }
}
#endif
