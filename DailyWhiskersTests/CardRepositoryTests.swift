import Testing
import UIKit
import ImageIO
import SQLite3
@testable import DailyWhiskers

@Suite("Immutable local cards", .serialized)
@MainActor
struct CardRepositoryTests {
    private func location() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("cards.sqlite")
    }
    private func sample(quote: String = "Original quote", color: UIColor = .red, imageName: String = "mutable") throws -> RetainedCard {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 30), format: format).image { c in
            color.setFill(); c.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
        }
        return try CardSnapshot.capture(card: DailyCard(id: "stable-cat", archetype: "cozy", imageName: imageName,
            quote: quote, vibe: "Exact vibe"), artwork: #require(image.pngData()))
    }
    private func sql(_ url: URL, _ sql: String) throws {
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
    }

    @Test func savedPresentationMatchesStateAndNextAction() {
        let unsaved = CardSaveState(isSaved: false)
        #expect(unsaved.actionLabel == "Save Card")
        #expect(unsaved.value == "Not saved")
        #expect(unsaved.hint == "Saves this card on this device.")
        #expect(unsaved.detailTitle == "Card")
        let saved = CardSaveState(isSaved: true)
        #expect(saved.actionLabel == "Remove from Saved Cards")
        #expect(saved.value == "Saved")
        #expect(saved.hint == "Removes this card from Saved Cards.")
        #expect(saved.detailTitle == "Saved Card")
    }

    @Test func originalCatArtworkUsesTransparentTemplateAndDistinctSavedBadge() throws {
        let unsaved = HeartEyesCatIcon.unsavedImage
        let saved = HeartEyesCatIcon.savedImage
        for image in [unsaved, saved] {
            #expect(image.renderingMode == .alwaysTemplate)
            #expect(image.size == CGSize(width: 32, height: 32))
            let cg = try #require(image.cgImage)
            #expect(cg.alphaInfo == .premultipliedLast || cg.alphaInfo == .premultipliedFirst)
        }
        // Saving adds a badge without changing the icon's size or replacing the cat.
        #expect(try #require(unsaved.pngData()) != #require(saved.pngData()))
    }

    @Test func clearEligibilityTracksRefreshSaveRemovalAndClear() async throws {
        let url = try location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = CardRepository(url: url)
        let model = SavedCardsModel(repository: repository)
        let first = try sample(), second = try sample(quote: "Second card")
        #expect(!model.canClear)
        await model.refresh()
        #expect(!model.canClear)
        await model.toggle(first)
        #expect(model.canClear)
        await model.toggle(second)
        await model.toggle(first)
        #expect(model.canClear) // Removing one of two must not disable Clear.
        await model.toggle(second)
        #expect(!model.canClear)
        await model.toggle(first) // Re-save retained content after removal.
        #expect(model.canClear)
        await model.clear()
        #expect(!model.canClear)
        try await repository.save(second)
        await model.refresh()
        #expect(model.canClear)
        await model.removeUnavailable(second.snapshot.id)
        #expect(!model.canClear)
        #expect(model.errorMessage == nil)
    }

    @Test func clearStaysDisabledWhilePopulatedStorageIsBusy() async throws {
        let url = try location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let card = try sample()
        try await CardRepository(url: url).save(card)
        let reachedCommit = AsyncStream<Void>.makeStream()
        let allowCommit = DispatchSemaphore(value: 0)
        let repository = CardRepository(url: url, beforeCommit: {
            reachedCommit.continuation.yield(())
            // Bound the test barrier so a failed assertion cannot stall storage.
            guard allowCommit.wait(timeout: .now() + 10) == .success else {
                throw CardStorageError.unavailable
            }
        })
        let model = SavedCardsModel(repository: repository)
        await model.refresh()
        #expect(model.canClear)
        let removal = Task { await model.toggle(card) }
        var commits = reachedCommit.stream.makeAsyncIterator()
        await commits.next()
        #expect(model.busy)
        #expect(!model.records.isEmpty)
        #expect(!model.canClear)
        allowCommit.signal()
        await removal.value
        reachedCommit.continuation.finish()
        #expect(!model.busy)
        #expect(!model.canClear)
        #expect(model.errorMessage == nil)
    }

    @Test func deterministicIdentityAndDistinctVersions() throws {
        let original = try sample()
        #expect(try sample(imageName: "renamed").snapshot.id == original.snapshot.id)
        #expect(try sample().snapshot.id == original.snapshot.id)
        #expect(try sample(quote: "Different quote").snapshot.id != original.snapshot.id)
        #expect(try sample(color: .blue).snapshot.id != original.snapshot.id)
        #expect(original.snapshot.quoteID == "legacy:stable-cat")
        #expect(original.snapshot.quoteRevision == ArtworkIdentity.checksum(Data("Original quote".utf8)))
    }

    @Test func persistenceIdempotenceOrderingAndOfflineUpgrade() async throws {
        let url = try location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = CardRepository(url: url)
        let old = try sample(), new = try sample(quote: "Updated quote", color: .blue)
        try await repository.save(old)
        try await repository.save(new)
        let before = try await repository.favorites()
        try await repository.save(old)
        let after = try await repository.favorites()
        #expect(after.map(\.id) == [new.snapshot.id, old.snapshot.id])
        #expect(after.map(\.sequence) == before.map(\.sequence))
        let reopened = CardRepository(url: url)
        let loaded = try await reopened.load(old.snapshot.id)
        #expect(loaded.snapshot == old.snapshot)
        #expect(loaded.artwork == old.artwork)
        let oldExport = try DailyCardShareRenderer.render(DailyCardShareSnapshot(retained: loaded))
        let freshExport = try DailyCardShareRenderer.render(DailyCardShareSnapshot(retained: new))
        #expect(oldExport.image.pngData() != freshExport.image.pngData())
        #expect(oldExport.text.contains("Original quote"))
        try await reopened.remove(new.snapshot.id)
        #expect(try await reopened.favorites().map(\.id) == [old.snapshot.id])
    }

    @Test func differentPNGEncodingWithIdenticalPixelsKeepsFirstSave() async throws {
        let url = try location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let original = try sample()
        let source = try #require(CGImageSourceCreateWithData(original.artwork as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let encoded = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(encoded, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyPNGDictionary:
            [kCGImagePropertyPNGDescription: "Different metadata, same pixels"]] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let alternative = try CardSnapshot.capture(card: DailyCard(id: "stable-cat", archetype: "cozy", imageName: "renamed",
            quote: original.snapshot.quote, vibe: original.snapshot.vibe), artwork: encoded as Data)
        #expect(alternative.snapshot.artworkChecksum != original.snapshot.artworkChecksum)
        #expect(alternative.snapshot.id == original.snapshot.id)
        let repository = CardRepository(url: url)
        try await repository.save(original); try await repository.save(alternative)
        #expect(try await repository.favorites().count == 1)
        #expect(try await repository.load(original.snapshot.id).artwork == original.artwork)
    }

    @Test func concurrentDuplicateSaves() async throws {
        let url = try location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = CardRepository(url: url), card = try sample()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<10 { group.addTask { try await repository.save(card) } }
            try await group.waitForAll()
        }
        #expect(try await repository.favorites().count == 1)
    }

    @Test func failedCommitAndInterruptedTransactionPreservePreviousRows() async throws {
        let url = try location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = CardRepository(url: url), old = try sample(), new = try sample(quote: "New")
        try await repository.save(old)
        // SQLITE_FULL injection after all rows are written but before COMMIT.
        let failing = CardRepository(url: url, beforeCommit: { throw CardStorageError.database(SQLITE_FULL) })
        await #expect(throws: Error.self) { try await failing.save(new) }
        await #expect(throws: Error.self) { try await failing.clearFavorites() }
        #expect(try await repository.favorites().map(\.id) == [old.snapshot.id])
        await #expect(throws: Error.self) { try await repository.load(new.snapshot.id) }
        try sql(url, "BEGIN IMMEDIATE; DELETE FROM favorite;") // closing uncommitted connection simulates interruption
        #expect(try await CardRepository(url: url).favorites().map(\.id) == [old.snapshot.id])
        try await repository.save(new) // retry on writable storage commits normally
        #expect(try await repository.favorites().count == 2)
    }

    @Test func corruptOrMissingArtworkNeverFallsBack() async throws {
        let url = try location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = CardRepository(url: url), card = try sample()
        try await repository.save(card)
        try sql(url, "UPDATE artwork SET bytes=x'010203'")
        await #expect(throws: Error.self) { try await repository.load(card.snapshot.id) }
        #expect(try await repository.favorites().count == 1) // still visible, explicitly unavailable
        await #expect(throws: Error.self) { try await repository.save(card) }
        try sql(url, "DELETE FROM artwork")
        await #expect(throws: Error.self) { try await repository.load(card.snapshot.id) }
    }

    @Test func unknownSchemaAndFailedInitialMigrationAreNondestructive() async throws {
        let url = try location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = CardRepository(url: url), card = try sample()
        try await repository.save(card)
        try sql(url, "PRAGMA user_version=999")
        await #expect(throws: Error.self) { try await CardRepository(url: url).favorites() }
        try sql(url, "PRAGMA user_version=1")
        #expect(try await CardRepository(url: url).load(card.snapshot.id).artwork == card.artwork)
        let failedURL = try location(); defer { try? FileManager.default.removeItem(at: failedURL.deletingLastPathComponent()) }
        let failing = CardRepository(url: failedURL, beforeCommit: { throw CardStorageError.database(SQLITE_FULL) })
        await #expect(throws: Error.self) { try await failing.favorites() }
        #expect(try await CardRepository(url: failedURL).favorites().isEmpty)
    }

    @Test func clearPreservesDayReferencesAndActiveSharesAndBackupRestoresTogether() async throws {
        let url = try location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = CardRepository(url: url), card = try sample(), other = try sample(quote: "Other")
        try await repository.save(card); try await repository.save(other)
        try sql(url, "INSERT INTO day_selection VALUES('2026-10-17','today','\(card.snapshot.id)','UTC')")
        let (lease, _) = try await repository.beginShare(other.snapshot.id)
        let backup = url.deletingLastPathComponent().appendingPathComponent("backup.sqlite")
        try await repository.backup(to: backup)
        try await repository.clearFavorites()
        #expect(try await repository.favorites().isEmpty)
        #expect(try await repository.load(card.snapshot.id).artwork == card.artwork)
        #expect(try await repository.load(other.snapshot.id).artwork == other.artwork)
        try await repository.endShare(lease)
        await #expect(throws: Error.self) { try await repository.load(other.snapshot.id) }
        let restored = CardRepository(url: backup)
        #expect(try await restored.favorites().count == 2)
        try await restored.clearFavorites()
        #expect(try await restored.load(card.snapshot.id).artwork == card.artwork)
        let values = try url.deletingLastPathComponent().resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup != true)
    }

    @Test func mismatchedSnapshotImportFailsWithoutReplacingPriorSave() async throws {
        let url = try location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = CardRepository(url: url), original = try sample(), different = try sample(color: .blue)
        try await repository.save(original)
        let mismatched = RetainedCard(snapshot: original.snapshot, artwork: different.artwork)
        await #expect(throws: Error.self) { try await repository.save(mismatched) }
        #expect(try await repository.load(original.snapshot.id).artwork == original.artwork)
        #expect(try await repository.favorites().count == 1)
    }

    @Test func explicitFutureQuoteIdentityPreservesLegacySnapshots() throws {
        let old = try sample()
        let new = try CardSnapshot.capture(card: DailyCard(id: "stable-cat", archetype: "cozy", imageName: "mutable",
            quote: old.snapshot.quote, vibe: old.snapshot.vibe), artwork: old.artwork, quoteID: "curated-quote-1", quoteRevision: "1")
        #expect(new.snapshot.id != old.snapshot.id)
        #expect(new.snapshot.quote == old.snapshot.quote)
        try old.snapshot.validate(artwork: old.artwork)
        try new.snapshot.validate(artwork: new.artwork)
    }

    @Test func bundledOriginalBytesAndDisplayedPixelsMatch() throws {
        let url = try #require(Bundle.main.url(forResource: "daily_whiskers_content", withExtension: "json"))
        let manifest = try JSONDecoder().decode(DailyContentManifest.self, from: Data(contentsOf: url))
        for card in manifest.cards {
            try autoreleasepool {
                let original = try BundledCardArtwork.bytes(for: card)
                let displayed = try #require(BundledCardArtwork.image(named: card.imageName)?.cgImage)
                #expect(try ArtworkIdentity.pixelDigest(original) == ArtworkIdentity.pixelDigest(displayed))
                let snapshot = try CardSnapshot.capture(card: card, artwork: original)
                #expect(snapshot.artwork == original)
            }
        }
    }
}
