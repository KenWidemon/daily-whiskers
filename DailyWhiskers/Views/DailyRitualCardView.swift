import SwiftUI

struct DailyCardData {
    let archetype: String
    let imageName: String
    let quote: String
    let vibe: String
}

struct ArchetypeTheme {
    let bgTop: Color
    let bgBottom: Color
    let glow: Color
    let frameA: Color
    let frameB: Color
    let text: Color
    let quote: Color
    let pillFill: Color
    let pillStroke: Color

    static func forArchetype(_ archetype: String) -> ArchetypeTheme {
        switch archetype.lowercased() {
        case "arcane":
            return .init(
                bgTop: Color(red: 0.20, green: 0.16, blue: 0.30),
                bgBottom: Color(red: 0.06, green: 0.05, blue: 0.10),
                glow: Color(red: 0.65, green: 0.52, blue: 0.90),
                frameA: Color(red: 0.98, green: 0.80, blue: 0.45),
                frameB: Color(red: 0.86, green: 0.62, blue: 0.98),
                text: .white,
                quote: Color.white.opacity(0.92),
                pillFill: Color.white.opacity(0.10),
                pillStroke: Color.white.opacity(0.25)
            )
        case "forest":
            return .init(
                bgTop: Color(red: 0.12, green: 0.22, blue: 0.16),
                bgBottom: Color(red: 0.04, green: 0.07, blue: 0.05),
                glow: Color(red: 0.30, green: 0.65, blue: 0.45),
                frameA: Color(red: 0.98, green: 0.80, blue: 0.45),
                frameB: Color(red: 0.86, green: 0.62, blue: 0.28),
                text: .white,
                quote: Color.white.opacity(0.92),
                pillFill: Color.white.opacity(0.10),
                pillStroke: Color.white.opacity(0.25)
            )
        case "alchemy":
            return .init(
                bgTop: Color(red: 0.25, green: 0.14, blue: 0.12),
                bgBottom: Color(red: 0.06, green: 0.04, blue: 0.06),
                glow: Color(red: 1.00, green: 0.68, blue: 0.38),
                frameA: Color(red: 1.00, green: 0.82, blue: 0.48),
                frameB: Color(red: 0.96, green: 0.62, blue: 0.30),
                text: .white,
                quote: Color.white.opacity(0.92),
                pillFill: Color.white.opacity(0.10),
                pillStroke: Color.white.opacity(0.25)
            )
        case "noble":
            return .init(
                bgTop: Color(red: 0.20, green: 0.12, blue: 0.08),
                bgBottom: Color(red: 0.06, green: 0.04, blue: 0.04),
                glow: Color(red: 1.00, green: 0.76, blue: 0.38),
                frameA: Color(red: 1.00, green: 0.84, blue: 0.52),
                frameB: Color(red: 0.92, green: 0.62, blue: 0.22),
                text: .white,
                quote: Color.white.opacity(0.92),
                pillFill: Color.white.opacity(0.10),
                pillStroke: Color.white.opacity(0.25)
            )
        case "celestial":
            return .init(
                bgTop: Color(red: 0.14, green: 0.10, blue: 0.24),
                bgBottom: Color(red: 0.05, green: 0.05, blue: 0.12),
                glow: Color(red: 0.55, green: 0.75, blue: 1.00),
                frameA: Color(red: 0.92, green: 0.86, blue: 1.00),
                frameB: Color(red: 0.60, green: 0.82, blue: 1.00),
                text: .white,
                quote: Color.white.opacity(0.92),
                pillFill: Color.white.opacity(0.10),
                pillStroke: Color.white.opacity(0.25)
            )
        default: // cozy
            return .init(
                bgTop: Color(red: 0.22, green: 0.14, blue: 0.18),
                bgBottom: Color(red: 0.07, green: 0.05, blue: 0.07),
                glow: Color(red: 1.00, green: 0.72, blue: 0.50),
                frameA: Color(red: 1.00, green: 0.84, blue: 0.56),
                frameB: Color(red: 0.98, green: 0.66, blue: 0.38),
                text: .white,
                quote: Color.white.opacity(0.92),
                pillFill: Color.white.opacity(0.10),
                pillStroke: Color.white.opacity(0.25)
            )
        }
    }
}

struct DailyRitualCardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize
    let data: DailyCardData
    var retainedArtwork: UIImage? = nil
    var accessibilityPrefix = "daily-card"
    private var theme: ArchetypeTheme { .forArchetype(data.archetype) }

    var body: some View {
        ZStack {
            CosmicBackground(theme: theme, reduceMotion: reduceMotion)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            GeometryReader { geometry in
                let availableWidth = max(0, geometry.size.width - 44)
                let artwork = retainedArtwork ?? BundledCardArtwork.image(named: data.imageName)
                let compact = CardViewportLayout.fitsPortrait(size: geometry.size, textSize: textSize)
                let roomy = min(geometry.size.width, geometry.size.height) >= 600
                let padding: CGFloat = compact ? 12 : 28
                let viewport = CGSize(width: availableWidth, height: max(0, geometry.size.height - padding * 2))
                ScrollView {
                    AdaptiveRitualCardPresentation(data: data, artwork: artwork, viewport: viewport,
                                                   compact: compact, tightQuotePanel: roomy,
                                                   accessibilityPrefix: accessibilityPrefix)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("\(accessibilityPrefix)-frame")
                    .padding(.vertical, padding)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height)
                }
                .accessibilityIdentifier("\(accessibilityPrefix)-content")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Content-driven selection: a natural-height stack, then height-aware columns when
/// readable, then a natural-height scrolling stack. No device or orientation rule.
struct AdaptiveRitualCardPresentation: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let data: DailyCardData
    let artwork: UIImage?
    let viewport: CGSize
    var compact: Bool
    var tightQuotePanel: Bool
    var accessibilityPrefix = "card"

    private var stacked: some View {
        RitualCardPresentation(data: data, artwork: artwork, compact: compact,
                               tightQuotePanel: tightQuotePanel, accessibilityPrefix: accessibilityPrefix)
            .frame(width: min(viewport.width, 520)).fixedSize(horizontal: false, vertical: true)
    }

    var body: some View {
        CardViewportProposal(size: viewport) {
            ViewThatFits(in: .vertical) {
                stacked
                if let columns = CardColumnSizing(viewport: viewport, artwork: artwork, textSize: textSize) {
                    RitualCardPresentation(data: data, artwork: artwork, compact: false,
                                           tightQuotePanel: true, sideBySide: true,
                                           artworkColumnWidth: columns.artworkWidth,
                                           quoteColumnWidth: columns.quoteWidth,
                                           accessibilityPrefix: accessibilityPrefix)
                        .fixedSize()
                }
                // No fitting candidate: let the outer ScrollView expose all content.
                stacked
            }
        }
    }
}

/// A column candidate must leave both a useful uncropped image and readable text.
/// Text is still measured by ViewThatFits; these bounds never force it to fit.
struct CardColumnSizing {
    let artworkWidth: CGFloat
    let quoteWidth: CGFloat

    init?(viewport: CGSize, artwork: UIImage?, textSize: DynamicTypeSize) {
        guard !textSize.isAccessibilitySize else { return nil }
        let aspect = max(artwork.map { $0.size.width / $0.size.height } ?? 2 / 3, 0.01)
        let width = min(520, viewport.height * aspect, viewport.width - 320)
        guard width >= 300 else { return nil }
        artworkWidth = width
        quoteWidth = min(440, viewport.width - width)
    }
}

/// The card's shared visual content, independent of screen controls and scrolling.
/// Export uses the ordinary-phone typography with natural, uncropped artwork height.
struct RitualCardPresentation: View {
    let data: DailyCardData
    let artwork: UIImage?
    var compact: Bool
    var maximumHeight: CGFloat? = nil
    // Screen-only variants; export defaults remain unchanged.
    var tightQuotePanel = false
    var sideBySide = false
    var artworkColumnWidth: CGFloat = 520
    var quoteColumnWidth: CGFloat = 440
    var accessibilityPrefix = "card"
    private var theme: ArchetypeTheme { .forArchetype(data.archetype) }

    var body: some View {
        RitualCard(theme: theme) {
            if sideBySide {
                HStack(spacing: 0) {
                    artworkContent.frame(width: artworkColumnWidth, height: artworkColumnWidth / artworkAspectRatio)
                    quotePanel.frame(width: quoteColumnWidth)
                }
                .fixedSize(horizontal: true, vertical: true)
            } else {
                CardViewportLayout(artworkAspectRatio: artworkAspectRatio, maximumHeight: maximumHeight) {
                    artworkContent
                    quotePanel
                }
            }
        }
    }

    private var artworkAspectRatio: CGFloat {
        max(artwork.map { $0.size.width / $0.size.height } ?? 2 / 3, 0.01)
    }

    @ViewBuilder private var artworkContent: some View {
        if let artwork {
            Image(uiImage: artwork).resizable().scaledToFit().accessibilityHidden(true)
        } else {
            Text("Artwork unavailable").foregroundStyle(.white).padding()
        }
    }

    private var quotePanel: some View {
        VStack(spacing: compact ? 8 : (tightQuotePanel ? 10 : 18)) {
            QuoteBlock(text: data.quote, theme: theme, compact: compact,
                       tightSpacing: tightQuotePanel, prominent: sideBySide)
                .accessibilityIdentifier("\(accessibilityPrefix)-quote")
            if !data.vibe.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VibePill(text: data.vibe.uppercased(), theme: theme, compact: compact)
                    .accessibilityIdentifier("\(accessibilityPrefix)-vibe")
            }
        }
        .padding(.horizontal, compact ? 16 : 24)
        .padding(.vertical, compact || tightQuotePanel ? 18 : 30)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: sideBySide ? .infinity : nil)
        .background {
            LinearGradient(colors: [.black.opacity(0.70), .black.opacity(0.86)],
                           startPoint: .top, endPoint: .bottom)
                .overlay(alignment: .top) {
                    LinearGradient(colors: [.clear, .black.opacity(0.70)], startPoint: .top, endPoint: .bottom)
                        .frame(height: compact || sideBySide ? 0 : 64)
                        .offset(y: compact || sideBySide ? 0 : -64)
                }
        }
    }
}

/// Give ViewThatFits the real visible height even inside a vertical ScrollView.
/// Return the selected child's natural size, so an oversized fallback can scroll.
struct CardViewportProposal: Layout {
    let size: CGSize
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews[0].sizeThatFits(ProposedViewSize(size))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(size))
    }
}

/// Measures text at its requested Dynamic Type size before fitting uncropped artwork.
/// When the measured text leaves too little artwork space, natural height scrolls.
struct CardViewportLayout: Layout {
    let artworkAspectRatio: CGFloat
    var maximumHeight: CGFloat?

    static func fitsPortrait(size: CGSize, textSize: DynamicTypeSize) -> Bool {
        size.width < 600 && size.height > size.width && !textSize.isAccessibilitySize
    }

    private func dimensions(_ proposal: ProposedViewSize, _ subviews: Subviews) -> (CGFloat, CGFloat, CGFloat) {
        let width = max(0, proposal.width ?? 320)
        let textHeight = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        let naturalArtwork = width / max(artworkAspectRatio, 0.01)
        let available = (maximumHeight ?? .infinity) - textHeight
        // Never shrink artwork to a token sliver to force unusually long text to fit.
        let artworkHeight = available >= 160 ? min(naturalArtwork, available) : naturalArtwork
        return (width, artworkHeight, textHeight)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let (width, artwork, text) = dimensions(proposal, subviews)
        return CGSize(width: width, height: artwork + text)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (width, artwork, text) = dimensions(ProposedViewSize(width: bounds.width, height: nil), subviews)
        subviews[0].place(at: CGPoint(x: bounds.midX, y: bounds.minY), anchor: .top, proposal: ProposedViewSize(width: width, height: artwork))
        subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + artwork), proposal: ProposedViewSize(width: width, height: text))
    }
}

struct CosmicBackground: View {
    let theme: ArchetypeTheme
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [theme.bgTop, theme.bgBottom],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    theme.glow.opacity(0.45),
                    Color.clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 520
            )
            .blendMode(.screen)

            SparkleField(reduceMotion: reduceMotion)
                .compositingGroup()
                .blendMode(.plusLighter)
                .opacity(0.4)
                .accessibilityHidden(true)
        }
    }
}

private struct RitualCard<Content: View>: View {
    let theme: ArchetypeTheme
    let content: Content

    init(
        theme: ArchetypeTheme,
        @ViewBuilder content: () -> Content
    ) {
        self.theme = theme
        self.content = content()
    }

    var body: some View {
        ZStack {
            content
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

        }
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.18))
                .blur(radius: 0.2)
        )
        .shadow(color: theme.glow.opacity(0.45), radius: 22, x: 0, y: 12)
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [theme.frameA, theme.frameB],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
                .shadow(color: theme.frameA.opacity(0.35), radius: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                .padding(2)
        )
    }
}

private struct QuoteBlock: View {
    let text: String
    let theme: ArchetypeTheme
    var compact = false
    var tightSpacing = false
    var prominent = false

    var body: some View {
        VStack(spacing: compact ? 0 : (tightSpacing ? 6 : 14)) {
            if !compact { HStack {
                Text("“")
                    .font(.system(.title, design: .serif).weight(.semibold))
                    .foregroundStyle(theme.quote.opacity(0.75))
                    .accessibilityHidden(true)
                Spacer()
            } }

            Text(text)
                .font(.system(prominent ? .largeTitle : (compact ? .title3 : .title2), design: .serif).weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.quote)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

            if !compact { HStack {
                Spacer()
                Text("”")
                    .font(.system(.title, design: .serif).weight(.semibold))
                    .foregroundStyle(theme.quote.opacity(0.75))
                    .accessibilityHidden(true)
            } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

private struct VibePill: View {
    let text: String
    let theme: ArchetypeTheme
    var compact = false

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .tracking(1.5)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(theme.text.opacity(0.92))
            .padding(.horizontal, 18)
            .padding(.vertical, compact ? 6 : 10)
            .background(
                Capsule(style: .continuous)
                    .fill(theme.pillFill)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(theme.pillStroke, lineWidth: 1)
                    )
                    .shadow(color: theme.glow.opacity(0.35), radius: 10, y: 6)
            )
            .accessibilityLabel("Vibe: \(text)")
    }
}

private struct SparkleField: View {
    @Environment(\.scenePhase) private var scenePhase
    let reduceMotion: Bool

    var body: some View {
        if reduceMotion {
            Canvas { context, size in
                drawSparkles(context: context, size: size, time: 0, animated: false)
            }
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: scenePhase != .active)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate

                Canvas { context, size in
                    drawSparkles(context: context, size: size, time: t, animated: true)
                }
            }
        }
    }

    private func drawSparkles(context: GraphicsContext, size: CGSize, time: Double, animated: Bool) {
        let dotCount = animated ? 120 : 48

        for index in 0..<dotCount {
            let phase = Double(pseudoRandom(index: index, seed: 0.17)) * Double.pi * 2
            let speed = 0.35 + Double(pseudoRandom(index: index, seed: 0.41)) * 0.8
            let twinkle = animated ? (sin(time * speed + phase) + 1) / 2 : 0.4

            let baseX = pseudoRandom(index: index, seed: 0.73) * size.width
            // bias upward so it feels like “cosmic dust” near the top of the screen
            let yBias = pow(pseudoRandom(index: index, seed: 0.39), 1.35)
            let baseY = yBias * size.height

            // gentle drift so sparkles feel alive
            let driftX = animated ? CGFloat(sin(time * 0.18 + phase)) * 0.8 : 0
            let driftY = animated ? CGFloat(cos(time * 0.14 + phase)) * 0.6 : 0

            let x = baseX + driftX
            let y = baseY + driftY

            let baseRadius = 1.2 + pseudoRandom(index: index, seed: 0.11) * 2.0
            let radius = baseRadius + CGFloat(twinkle) * (animated ? 1.4 : 0.6)

            let baseAlpha = 0.05 + pseudoRandom(index: index, seed: 0.91) * 0.08
            let alpha = min(0.28, baseAlpha + CGFloat(twinkle) * (animated ? 0.14 : 0.06))

            let tintMix = pseudoRandom(index: index, seed: 0.66)
            let sparkleColor: Color = (tintMix > 0.65)
                ? Color(red: 1.0, green: 0.96, blue: 0.90)
                : Color(red: 0.93, green: 0.95, blue: 1.0)

            let rect = CGRect(x: x, y: y, width: radius, height: radius)
            context.fill(
                Path(ellipseIn: rect),
                with: .color(sparkleColor.opacity(alpha))
            )

            if index % 14 == 0 {
                let starRadius = radius * (2.6 + CGFloat(twinkle) * 0.9)
                let starRect = CGRect(
                    x: x - starRadius * 0.35,
                    y: y - starRadius * 0.35,
                    width: starRadius,
                    height: starRadius
                )
                context.fill(
                    Path(ellipseIn: starRect),
                    with: .color(sparkleColor.opacity(min(0.22, alpha * 0.85)))
                )
            }
        }
    }

    private func pseudoRandom(index: Int, seed: Double) -> CGFloat {
        let value = sin(Double(index) * 12.9898 + seed * 78.233) * 43758.5453
        return CGFloat(value - floor(value))
    }
}
