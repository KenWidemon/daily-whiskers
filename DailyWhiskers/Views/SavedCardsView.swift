import SwiftUI
import ImageIO

struct SavedCardsView: View {
    @ObservedObject var model: SavedCardsModel
    @Environment(\.dynamicTypeSize) private var textSize
    private let theme = ArchetypeTheme.forArchetype("celestial")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("On this device").font(.headline)
                    Text("Saved on this device. Daily Whiskers does not sync your saved cards. Your device backup may include them.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if model.records.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: CardSaveState(isSaved: false).symbol).font(.largeTitle).accessibilityHidden(true)
                        Text("Save a card to come back to it.")
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("saved-cards-empty")
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 44)
                }
                LazyVGrid(columns: [GridItem(textSize.isAccessibilitySize ? .flexible() : .adaptive(minimum: 300), spacing: 20)], spacing: 20) {
                    ForEach(model.records) { record in
                        NavigationLink {
                            SavedCardDetail(id: record.id, model: model)
                        } label: {
                            VStack(alignment: .leading, spacing: 16) {
                                SavedCardThumbnail(id: record.id)
                                HStack(alignment: .center, spacing: 12) {
                                    Text(record.quote)
                                        .font(.system(.body, design: .serif))
                                        .lineLimit(textSize.isAccessibilitySize ? nil : 3)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                                        .foregroundStyle(.secondary).accessibilityHidden(true)
                                }
                            }
                            .padding(16)
                            .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 24))
                            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.16), lineWidth: 1))
                            .contentShape(RoundedRectangle(cornerRadius: 24))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(record.quote)
                        .accessibilityHint("Opens the saved card.")
                        .accessibilityIdentifier("saved-card-row")
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: textSize.isAccessibilitySize ? 560 : 780)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("saved-cards-collection")
        .background {
            CosmicBackground(theme: theme, reduceMotion: true)
                .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
        }
        .navigationTitle("Saved Cards")
        .task { await model.refresh() }
        .modifier(SavedCardsError(model: model))
    }
}

/// Visible tiles retain only display-sized decoded thumbnails, never original blobs.
private struct SavedCardThumbnail: View {
    let id: String
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else { Image(systemName: "photo").foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity).frame(height: 240)
        .accessibilityHidden(true)
        .task(id: id) {
            guard let card = try? await CardRepository.shared.load(id),
                  let source = CGImageSourceCreateWithData(card.artwork as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 240 * displayScale,
                    kCGImageSourceCreateThumbnailWithTransform: true
                  ] as CFDictionary), !Task.isCancelled else { return }
            image = UIImage(cgImage: thumbnail)
        }
        .onDisappear { image = nil }
    }
}

struct SavedCardDetail: View {
    let id: String
    @ObservedObject var model: SavedCardsModel
    @State private var card: RetainedCard?
    @State private var errorMessage: String?
    @StateObject private var share = DailyCardShareState()
    @AccessibilityFocusState private var optionsFocused: Bool
    @AccessibilityFocusState private var shareFocused: Bool

    private var saveState: CardSaveState { CardSaveState(isSaved: model.contains(id)) }

    var body: some View {
        Group {
            if let card, let image = UIImage(data: card.artwork) {
                // Render the retained snapshot with the same presentation as Today.
                // Never resolve saved content through the current manifest or an asset name.
                DailyRitualCardView(
                    data: DailyCardData(archetype: card.snapshot.archetype, imageName: "",
                                        quote: card.snapshot.quote, vibe: card.snapshot.vibe ?? ""),
                    retainedArtwork: image,
                    accessibilityPrefix: "saved-card"
                )
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Saved Card Unavailable", systemImage: "exclamationmark.triangle")
                } description: { Text(errorMessage) } actions: {
                    Button("Try Again") { Task { await load() } }
                    if model.contains(id) {
                        Button("Remove from Saved Cards", role: .destructive) {
                            Task { await model.removeUnavailable(id) }
                        }
                    }
                }
            } else { ProgressView("Opening saved card") }
        }
        .navigationTitle(saveState.detailTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: id) { await load() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    guard let card else { return }
                    Task { await share.start(retained: card) }
                } label: {
                    Group {
                        if share.isRendering { ProgressView() }
                        else { Image(systemName: "square.and.arrow.up") }
                    }.frame(minWidth: 44, minHeight: 44)
                }
                .disabled(card == nil || share.isRendering || share.export != nil)
                .accessibilityLabel(share.isRendering ? "Preparing Card" : (saveState.isSaved ? "Share Saved Card" : "Share Card"))
                .accessibilityHint("Shares the retained artwork and quote. You choose where to send it.")
                .accessibilityFocused($shareFocused)
                .background {
                    DailyCardShareSheet(export: share.export) { failed in
                        share.completeActivity(failed: failed)
                        share.sheetDismissed()
                        shareFocused = true
                    }.allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: model.contains(id) ? .destructive : nil) {
                        guard let card else { return }
                        Task { await model.toggle(card); optionsFocused = true }
                    } label: {
                        Label(saveState.actionLabel, systemImage: saveState.actionSymbol)
                    }
                    .accessibilityIdentifier("saved-card-toggle")
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .disabled(card == nil || model.busy || share.isRendering || share.export != nil)
                .accessibilityLabel(saveState.isSaved ? "Saved Card Options" : "Card Options")
                .accessibilityHint("Opens save and remove actions for this card.")
                .accessibilityValue(saveState.value)
                .accessibilityIdentifier("saved-card-options")
                .accessibilityFocused($optionsFocused)
            }
        }
        .modifier(SavedCardsError(model: model))
        .alert("Couldn't Share Card", isPresented: $share.hasError) {
            Button("Try Again") { Task { await share.retry() } }
            Button("Cancel", role: .cancel) { share.finish(); shareFocused = true }
        } message: { Text("The saved card couldn't be prepared or shared. Please try again.") }
    }

    private func load() async {
        errorMessage = nil
        card = nil
        do {
            let loaded = try await CardRepository.shared.load(id)
            guard !Task.isCancelled else { return }
            card = loaded
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "The original saved content is unavailable. Try again."
        }
    }
}
