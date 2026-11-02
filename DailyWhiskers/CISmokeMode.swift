#if DEBUG && CI_SMOKE_TESTING
import Foundation
import UIKit
import SwiftUI

// Compiled only by the dedicated CI Debug command, never the Release app.
// No fake successful authentication: unexpected backend calls fail closed.
enum CISmokeMode {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("--ci-smoke") }

    // A validated per-test UUID selects disposable storage; never touch the ordinary collection.
    static var savedCardsFixtureURL: URL? {
        guard isEnabled,
              ProcessInfo.processInfo.arguments.contains("--ci-smoke-saved-load-fixture"),
              let value = ProcessInfo.processInfo.environment["DW_SAVED_LOAD_TEST_ID"],
              let id = UUID(uuidString: value) else { return nil }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("SavedLoadFixtures/" + id.uuidString)
            .appendingPathComponent("cards.sqlite")
    }

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

/// Real collection view and SQLite content, with a deterministic read boundary.
/// The first read waits for the UI test, then fails; the next succeeds. A later
/// refresh fails once more. No corruption, reset or owner data is involved.
@MainActor
private final class SavedCardsFixtureReader {
    private var attempt = 0
    private var continuation: CheckedContinuation<Void, Never>?
    func read() async throws -> [FavoriteRecord] {
        attempt += 1
        if attempt == 1 {
            await withCheckedContinuation { continuation = $0 }
            throw CardStorageError.database(10)
        }
        if attempt == 2,
           ProcessInfo.processInfo.arguments.contains("--ci-smoke-saved-interrupted-retry") {
            await withCheckedContinuation { continuation = $0 }
            throw CancellationError()
        }
        if attempt == 3 { throw CardStorageError.database(10) }
        return try await CardRepository.shared.favorites()
    }
    func finishFirstRead() { continuation?.resume(); continuation = nil }
}

@MainActor
private final class SavedCardsLoadFixture: ObservableObject {
    let reader: SavedCardsFixtureReader
    let model: SavedCardsModel
    @Published var prepared = false
    @Published var error: String?
    init() {
        let reader = SavedCardsFixtureReader()
        self.reader = reader
        model = SavedCardsModel(readFavorites: { try await reader.read() })
    }
    func prepare() async {
        guard !prepared else { return }
        do {
            if !ProcessInfo.processInfo.arguments.contains("--ci-smoke-saved-empty-fixture") {
                let cards = DailyContentProvider().bonusCandidates.sorted { $0.id < $1.id }.prefix(2)
                guard cards.count == 2 else { throw CardStorageError.unavailable }
                for (index, card) in cards.enumerated() {
                    let fixture = DailyCard(id: card.id, archetype: card.archetype, imageName: card.imageName,
                        quote: index == 0 ? "First saved fixture." : "Second saved fixture.", vibe: card.vibe)
                    try await CardRepository.shared.save(CardSnapshot.capture(card: fixture,
                        artwork: BundledCardArtwork.bytes(for: card)))
                }
            }
            prepared = true
        } catch { self.error = String(describing: error) }
    }
}

struct SavedCardsLoadFixtureView: View {
    @StateObject private var fixture = SavedCardsLoadFixture()
    var body: some View {
        VStack(spacing: 0) {
            NavigationStack {
                Group {
                    if fixture.prepared { SavedCardsView(model: fixture.model) }
                    else if let error = fixture.error { Text(error) }
                    else { ProgressView("Preparing isolated fixture") }
                }
            }
            HStack(spacing: 24) {
                Button { fixture.reader.finishFirstRead() } label: {
                    Text("Finish pending read").frame(minHeight: 44)
                }
                .accessibilityIdentifier("fixture-finish-read")
                Button { Task { await fixture.model.refresh() } } label: {
                    Text("Refresh fixture").frame(minHeight: 44)
                }
                .accessibilityIdentifier("fixture-refresh")
            }
            .font(.caption).dynamicTypeSize(.medium)
            .padding(.bottom, 24) // Keep the app's offline marker and home gesture clear.
            .frame(maxWidth: .infinity).background(.black)
        }
        // Match DailyWhiskersView's app appearance without changing system settings.
        .preferredColorScheme(.dark)
        .task { await fixture.prepare() }
    }
}
#endif
