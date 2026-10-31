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
                        .font(.footnote).foregroundStyle(theme.quote)
                        .fixedSize(horizontal: false, vertical: true)
                }
                switch model.loadState {
                case .loading:
                    ProgressView("Loading Saved Cards…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("saved-cards-loading")
                case .unavailable:
                    VStack(alignment: .leading, spacing: 16) {
                        Group {
                            if textSize.isAccessibilitySize {
                                VStack(alignment: .leading, spacing: 12) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .accessibilityHidden(true)
                                    Text("Saved Cards Unavailable")
                                }
                                .accessibilityElement(children: .combine)
                            } else {
                                Label("Saved Cards Unavailable", systemImage: "exclamationmark.triangle")
                            }
                        }
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("saved-cards-unavailable")
                        Text(model.records.isEmpty
                             ? "Try again to load your collection."
                             : "Showing previously loaded cards. Retry to check for updates.")
                            .foregroundStyle(theme.quote)
                            .accessibilityIdentifier("saved-cards-read-status")
                        Button { Task { await model.refresh() } } label: {
                            Text("Retry").font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.roundedRectangle(radius: 16))
                            .tint(theme.frameA)
                            .foregroundStyle(theme.bgBottom)
                            .disabled(model.busy)
                            .accessibilityHint("Tries to load your saved cards again.")
                            .accessibilityIdentifier("saved-cards-retry")
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    // An opaque celestial surface keeps text/control contrast stable
                    // over the glow and stars; the collection's cosmic backdrop stays.
                    .background(theme.bgBottom, in: RoundedRectangle(cornerRadius: 24))
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.16), lineWidth: 1))
                case .loaded:
                    if model.records.isEmpty {
                        VStack(spacing: 16) {
                            CardSaveState(isSaved: false).icon
                                .resizable().frame(width: 40, height: 40).accessibilityHidden(true)
                            Text("Save a card to come back to it.")
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("saved-cards-empty")
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 44)
                    }
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
                                        .modifier(SavedQuoteLines(reserveSpace: UIDevice.current.userInterfaceIdiom == .pad,
                                                                  accessibilitySize: textSize.isAccessibilitySize))
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
#if DEBUG && CI_SMOKE_TESTING
                        .accessibilityValue(CISmokeMode.savedCardsFixtureURL != nil ? record.id : "")
#endif
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
        .task {
            // Preserve a failed read and reachable Retry when navigating from Today.
            if !model.isUnavailable { await model.refresh() }
        }
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
    @State private var optionsFocused: Bool = false

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
        .background { nativeToolbar.frame(width: 0, height: 0) }
        .modifier(SavedCardsError(model: model))
        .alert("Couldn't Share Card", isPresented: $share.hasError) {
            Button("Try Again") { Task { await share.retry() } }
            Button("Cancel", role: .cancel) { share.finish(); optionsFocused = true }
        } message: { Text("The saved card couldn't be prepared or shared. Please try again.") }
    }

    private var nativeToolbar: CardNavigationToolbar {
        let shareAction = CardNavigationToolbar.action(saveState.isSaved ? "Share Saved Card" : "Share Card",
            identifier: "saved-card-share", image: UIImage(systemName: "square.and.arrow.up"),
            hint: "Shares the retained artwork and quote. You choose where to send it.") {
                guard let card else { return }
                optionsFocused = false
                Task { await share.start(retained: card) }
            }
        let toggle = CardNavigationToolbar.action(saveState.actionLabel, identifier: "saved-card-toggle",
            image: saveState.isSaved ? HeartEyesCatIcon.savedImage : HeartEyesCatIcon.unsavedImage,
            hint: saveState.hint, value: saveState.value, destructive: saveState.isSaved) {
                guard let card else { return }
                Task { await model.toggle(card); optionsFocused = true }
            }
        return CardNavigationToolbar(options: .init(identifier: "saved-card-options",
            label: share.isRendering ? "Preparing Card" : (saveState.isSaved ? "Saved Card Options" : "Card Options"),
            hint: "Opens share, save, and remove actions for this card.", value: saveState.value,
            image: "ellipsis", enabled: card != nil && !model.busy && !share.isRendering && share.export == nil,
            menu: UIMenu(children: [shareAction, toggle])),
            export: share.export, onShareComplete: { failed in
                share.completeActivity(failed: failed); share.sheetDismissed(); optionsFocused = true
            }, optionsFocused: $optionsFocused, settingsFocused: .constant(false))
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

/// Reserve equal quote areas only on ordinary-size iPad tiles; accessibility
/// quotes expand completely and the phone keeps its existing natural tile height.
private struct SavedQuoteLines: ViewModifier {
    let reserveSpace: Bool
    let accessibilitySize: Bool
    func body(content: Content) -> some View {
        if accessibilitySize {
            content.lineLimit(nil)
        } else {
            content.lineLimit(3, reservesSpace: reserveSpace)
        }
    }
}
