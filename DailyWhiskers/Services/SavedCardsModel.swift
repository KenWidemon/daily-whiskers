import SwiftUI

@MainActor
final class SavedCardsModel: ObservableObject {
    @Published private(set) var records: [FavoriteRecord] = []
    @Published private(set) var busy = false
    @Published var errorMessage: String?
    private let repository: CardRepository
    private var retryAction: (() async -> Void)?

    init(repository: CardRepository = .shared) { self.repository = repository }
    var canClear: Bool { !busy && !records.isEmpty }
    func contains(_ id: String) -> Bool { records.contains { $0.id == id } }
    func refresh() async {
        await perform { self.records = try await self.repository.favorites() }
    }
    func toggle(_ card: RetainedCard) async {
        // Capture desired action before awaiting; retries never invert the original intent.
        let remove = contains(card.snapshot.id)
        await perform {
            if remove { try await self.repository.remove(card.snapshot.id) }
            else { try await self.repository.save(card) }
            self.records = try await self.repository.favorites()
            UIAccessibility.post(notification: .announcement, argument: remove ? "Removed from Saved Cards." : "Card saved.")
        }
    }
    func removeUnavailable(_ id: String) async {
        await perform {
            try await self.repository.remove(id)
            self.records = try await self.repository.favorites()
            UIAccessibility.post(notification: .announcement, argument: "Removed from Saved Cards.")
        }
    }
    func clear() async {
        await perform {
            try await self.repository.clearFavorites()
            self.records = try await self.repository.favorites()
            UIAccessibility.post(notification: .announcement, argument: "Saved Cards cleared.")
        }
    }
    func retry() async { await retryAction?() }
    func cancelError() { errorMessage = nil; retryAction = nil }
    private func perform(_ action: @escaping () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            try await action()
            retryAction = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Saved Cards is unavailable. Please try again."
            retryAction = { [weak self] in await self?.perform(action) }
        }
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
struct CardSaveState {
    let isSaved: Bool
    var symbol: String { isSaved ? "bookmark.fill" : "bookmark" }
    var actionSymbol: String { isSaved ? "bookmark.slash" : "bookmark" }
    var actionLabel: String { isSaved ? "Remove from Saved Cards" : "Save Card" }
    var value: String { isSaved ? "Saved" : "Not saved" }
    var hint: String { isSaved ? "Removes this card from Saved Cards." : "Saves this card on this device." }
    var detailTitle: String { isSaved ? "Saved Card" : "Card" }
}
