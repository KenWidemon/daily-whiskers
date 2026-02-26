import SwiftUI

struct DailyWhiskersView: View {
    @EnvironmentObject private var router: AppRouter

    private let provider = DailyContentProvider()

    var body: some View {
        NavigationStack {
            ZStack {
                if let entry = provider.contentForToday() {
                    DailyRitualCardView(
                        data: DailyCardData(
                            archetype: entry.archetype,
                            imageName: entry.imageName,
                            quote: entry.quote,
                            vibe: entry.vibe ?? ""
                        )
                    )
                } else {
                    ZStack {
                        Color(.systemGroupedBackground).ignoresSafeArea()
                        Text("No daily content found.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Log Out", role: .destructive) {
                            do {
                                try router.signOut()
                            } catch {
                                // Keep UI minimal for v1.
                            }
                        }
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Ritual Card (New V2 Daily Design)

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
    let data: DailyCardData
    private var theme: ArchetypeTheme { .forArchetype(data.archetype) }

    var body: some View {
        ZStack {
            CosmicBackground(theme: theme)

            RitualCard(theme: theme) {
                ZStack(alignment: .bottom) {
                    Image(data.imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .clipped()

                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.black.opacity(0.55),
                            Color.black.opacity(0.78)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 360)
                }
            } overlayContent: {
                VStack(spacing: 18) {
                    Spacer()

                    QuoteBlock(text: data.quote, theme: theme)
                        .padding(.horizontal, 28)

                    if !data.vibe.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VibePill(text: data.vibe.uppercased(), theme: theme)
                            .padding(.bottom, 24)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 34)
        }
        .ignoresSafeArea()
    }
}

private struct CosmicBackground: View {
    let theme: ArchetypeTheme

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

            SparkleField()
                .compositingGroup()
                .blendMode(.plusLighter)
                .opacity(0.4)
        }
    }
}

private struct RitualCard<Content: View, Overlay: View>: View {
    let theme: ArchetypeTheme
    let content: Content
    let overlay: Overlay

    init(
        theme: ArchetypeTheme,
        @ViewBuilder content: () -> Content,
        @ViewBuilder overlayContent: () -> Overlay
    ) {
        self.theme = theme
        self.content = content()
        self.overlay = overlayContent()
    }

    var body: some View {
        ZStack {
            content
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            overlay
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
        .aspectRatio(3/4, contentMode: .fit)
    }
}

private struct QuoteBlock: View {
    let text: String
    let theme: ArchetypeTheme

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("“")
                    .font(.system(size: 38, weight: .semibold, design: .serif))
                    .foregroundStyle(theme.quote.opacity(0.75))
                Spacer()
            }

            Text(text)
                .font(.system(size: 26, weight: .semibold, design: .serif))
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.quote)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

            HStack {
                Spacer()
                Text("”")
                    .font(.system(size: 38, weight: .semibold, design: .serif))
                    .foregroundStyle(theme.quote.opacity(0.75))
            }
        }
    }
}

private struct VibePill: View {
    let text: String
    let theme: ArchetypeTheme

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .tracking(1.5)
            .foregroundStyle(theme.text.opacity(0.92))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(theme.pillFill)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(theme.pillStroke, lineWidth: 1)
                    )
                    .shadow(color: theme.glow.opacity(0.35), radius: 10, y: 6)
            )
    }
}

private struct SparkleField: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                let dotCount = 120

                for index in 0..<dotCount {
                    let phase = Double(pseudoRandom(index: index, seed: 0.17)) * Double.pi * 2
                    let speed = 0.35 + Double(pseudoRandom(index: index, seed: 0.41)) * 0.8
                    let twinkle = (sin(t * speed + phase) + 1) / 2

                    let baseX = pseudoRandom(index: index, seed: 0.73) * size.width
                    // bias upward so it feels like “cosmic dust” near the top of the screen
                    let yBias = pow(pseudoRandom(index: index, seed: 0.39), 1.35)
                    let baseY = yBias * size.height

                    // gentle drift so sparkles feel alive
                    let driftX = CGFloat(sin(t * 0.18 + phase)) * 0.8
                    let driftY = CGFloat(cos(t * 0.14 + phase)) * 0.6

                    let x = baseX + driftX
                    let y = baseY + driftY

                    let baseRadius = 1.2 + pseudoRandom(index: index, seed: 0.11) * 2.0
                    let radius = baseRadius + CGFloat(twinkle) * 1.4

                    let baseAlpha = 0.05 + pseudoRandom(index: index, seed: 0.91) * 0.08
                    let alpha = min(0.28, baseAlpha + CGFloat(twinkle) * 0.14)

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
        }
    }

    private func pseudoRandom(index: Int, seed: Double) -> CGFloat {
        let value = sin(Double(index) * 12.9898 + seed * 78.233) * 43758.5453
        return CGFloat(value - floor(value))
    }
}
