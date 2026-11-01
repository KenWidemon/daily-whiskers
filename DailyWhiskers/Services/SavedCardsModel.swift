import SwiftUI

@MainActor
final class SavedCardsModel: ObservableObject {
    enum LoadState: Equatable {
        case loading
        case loaded
        case unavailable(String)
    }

    @Published private(set) var records: [FavoriteRecord] = []
    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var busy = false
    @Published var errorMessage: String?
    private let repository: CardRepository
    private let readFavorites: () async throws -> [FavoriteRecord]
    private var retryAction: (() async -> Void)?

    init(repository: CardRepository = .shared,
         readFavorites: (() async throws -> [FavoriteRecord])? = nil) {
        self.repository = repository
        self.readFavorites = readFavorites ?? { try await repository.favorites() }
    }
    var canClear: Bool { !busy && !records.isEmpty }
    var isUnavailable: Bool {
        if case .unavailable = loadState { return true }
        return false
    }
    func contains(_ id: String) -> Bool { records.contains { $0.id == id } }
    func refresh() async { await perform() }
    func toggle(_ card: RetainedCard) async {
        // Capture desired action before awaiting; retries never invert the original intent.
        let remove = contains(card.snapshot.id)
        await perform({
            if remove { try await self.repository.remove(card.snapshot.id) }
            else { try await self.repository.save(card) }
        }, announcement: remove ? "Removed from Saved Cards." : "Card saved.")
    }
    func removeUnavailable(_ id: String) async {
        await perform({ try await self.repository.remove(id) }, announcement: "Removed from Saved Cards.")
    }
    func clear() async {
        await perform({ try await self.repository.clearFavorites() }, announcement: "Saved Cards cleared.")
    }
    func retry() async { await retryAction?() }
    // Collection read status outlives the transient alert and its write retry.
    func cancelError() { errorMessage = nil; retryAction = nil }

    private func perform(_ mutation: (() async throws -> Void)? = nil, announcement: String? = nil) async {
        guard !busy else { return }
        busy = true
        errorMessage = nil
        retryAction = nil
        defer { busy = false }
        do {
            try await mutation?()
        } catch {
            errorMessage = message(for: error)
            retryAction = { [weak self] in await self?.perform(mutation, announcement: announcement) }
            return
        }
        // A committed mutation must never be replayed when only its readback failed.
        loadState = .loading
        do {
            let loaded = try await readFavorites()
            records = loaded
            loadState = .loaded
            if let announcement { UIAccessibility.post(notification: .announcement, argument: announcement) }
        } catch {
            let message = message(for: error)
            loadState = .unavailable(message)
            errorMessage = message
            retryAction = { [weak self] in await self?.refresh() }
        }
    }

    private func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "Saved Cards is unavailable. Please try again."
    }
}

struct SavedCardsError: ViewModifier {
    @ObservedObject var model: SavedCardsModel
    func body(content: Content) -> some View {
        content.alert("Couldn't Update Saved Cards", isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("Try Again") { Task { await model.retry() } }
            Button("Cancel", role: .cancel) { model.cancelError() }
        } message: { Text(model.errorMessage ?? "") }
    }
}

/// Shared visual state and next-action wording for Today, Bonus and retained detail.
@MainActor
struct CardSaveState {
    let isSaved: Bool
    var icon: Image { Image(uiImage: isSaved ? HeartEyesCatIcon.savedImage : HeartEyesCatIcon.unsavedImage) }
    var actionLabel: String { isSaved ? "Remove from Saved Cards" : "Save Card" }
    var value: String { isSaved ? "Saved" : "Not saved" }
    var hint: String { isSaved ? "Removes this card from Saved Cards." : "Saves this card on this device." }
    var detailTitle: String { isSaved ? "Saved Card" : "Card" }
}
