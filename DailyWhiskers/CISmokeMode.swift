#if DEBUG && CI_SMOKE_TESTING
import Foundation
import UIKit
import SwiftUI

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

/// A fresh preference domain plus the actual read-only OS motion state.
/// Each test supplies a new UUID; relaunches reuse it to exercise actual AppStorage writes.
struct CISmokeStillnessFixture: ViewModifier {
    private let preferences: UserDefaults?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    init() {
        if CISmokeMode.isEnabled,
           let identifier = ProcessInfo.processInfo.environment["DW_STILLNESS_TEST_ID"],
           UUID(uuidString: identifier) != nil {
            preferences = UserDefaults(suiteName: "dw.stillness.tests." + identifier)
        } else {
            preferences = nil
        }
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if let preferences {
            content
                .defaultAppStorage(preferences)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Text(systemReduceMotion ? "System Reduce Motion: On" : "System Reduce Motion: Off")
                        .accessibilityIdentifier("ci-stillness-system")
                        .font(.caption)
                        .dynamicTypeSize(.medium)
                        .padding(.horizontal)
                        .accessibilityHint("Read-only offline test precondition. Device settings are unchanged.")
                }
        } else {
            content
        }
    }
}
#endif
