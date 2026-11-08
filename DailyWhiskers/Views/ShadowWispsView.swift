import SwiftUI

// Revision-02 ribbons with responsive reach; decoration never changes card layout.
struct ShadowWispsView: View {
    let containerWidth: CGFloat
    @AppStorage(MotionPolicy.preferenceKey) private var stillness = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var animated: Bool { !stillness && !reduceMotion && scenePhase == .active }
    var body: some View {
        Group {
            if animated {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    // Main billows cycle in roughly 8–14 seconds; spatial paths stay unchanged.
                    ShadowWispCanvas(phase: context.date.timeIntervalSinceReferenceDate * .pi / 2,
                                     containerWidth: containerWidth)
#if DEBUG && CI_SMOKE_TESTING
                        .onChange(of: context.date) { _, _ in CISmokeShadowAudit.frame() }
#endif
                }
            } else {
                // Same fixed composition for every static policy. No timeline, timer,
                // repeatForever animation or display link exists in this branch.
                ShadowWispCanvas(phase: 0, containerWidth: containerWidth)
            }
        }
        .padding(-ShadowWispCanvas.margin)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
#if DEBUG && CI_SMOKE_TESTING
        .onChange(of: scenePhase, initial: true) { _, value in CISmokeShadowAudit.scene(value) }
#endif
    }
}

private struct ShadowWispCanvas: View {
    static let margin: CGFloat = 144
    let phase: Double
    let containerWidth: CGFloat

    // Deliberately asymmetric silhouettes; no evenly spaced repeated loops.
    private static let wisps: [Wisp] = [
        Wisp(side: -1, top: 0.03, length: 0.36, reach: 96, width: 25, bend: 0.4, speed: 0.43),
        Wisp(side: -1, top: 0.31, length: 0.24, reach: 126, width: 34, bend: 2.2, speed: 0.31),
        Wisp(side: -1, top: 0.57, length: 0.32, reach: 86, width: 22, bend: 4.1, speed: 0.52),
        Wisp(side: -1, top: 0.80, length: 0.17, reach: 66, width: 16, bend: 1.3, speed: 0.37),
        Wisp(side: 1, top: 0.08, length: 0.29, reach: 118, width: 30, bend: 3.2, speed: 0.34),
        Wisp(side: 1, top: 0.38, length: 0.39, reach: 78, width: 19, bend: 5.0, speed: 0.47),
        Wisp(side: 1, top: 0.68, length: 0.28, reach: 124, width: 32, bend: 0.9, speed: 0.29)
    ]

    var body: some View {
        Canvas { context, size in
            let card = CGRect(origin: CGPoint(x: Self.margin, y: Self.margin),
                              size: CGSize(width: max(0, size.width - Self.margin * 2),
                                           height: max(0, size.height - Self.margin * 2)))
            // Pull centerlines toward the card when exterior space is scarce.
            // Keep ribbon width/height and motion intact; roomy gutters use the
            // exact original paths. The mask still protects the card and moat.
            let gutter = max(0, (containerWidth - card.width) / 2)
            let reachScale = min(1, gutter / Self.margin)
            for wisp in Self.wisps {
                let edge = wisp.side < 0 ? card.minX : card.maxX
                let top = card.minY + card.height * wisp.top
                let length = card.height * wisp.length
                let ribbon = wisp.ribbon(edge: edge, top: top, length: length,
                                         phase: phase, reachScale: reachScale)
                let gradient = Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color(red: 0.025, green: 0.018, blue: 0.035).opacity(0.72), location: 0.22),
                    .init(color: Color(red: 0.055, green: 0.035, blue: 0.075).opacity(0.64), location: 0.64),
                    .init(color: .clear, location: 1)
                ])
                let ink = GraphicsContext.Shading.linearGradient(gradient,
                    startPoint: CGPoint(x: edge, y: top + length),
                    endPoint: CGPoint(x: edge, y: top))
                context.drawLayer { smoke in
                    smoke.addFilter(.blur(radius: 7))
                    smoke.fill(ribbon, with: ink)
                }
                context.fill(ribbon, with: ink)
            }
        }
        // Mask after blur: the whole card plus a three-point moat stays clear.
        // This remains a decorative overlay and does not change card geometry.
        .mask { ExteriorCardMask().fill(style: FillStyle(eoFill: true)) }
    }

    private struct Wisp {
        let side: Double
        let top: Double
        let length: Double
        let reach: Double
        let width: Double
        let bend: Double
        let speed: Double

        func ribbon(edge: Double, top: Double, length: Double, phase: Double, reachScale: Double) -> Path {
            let time = phase * speed
            // Incommensurate oscillations produce a slow billow and a smaller curl.
            // Geometry is deterministic at phase zero for every static policy.
            func center(_ t: Double) -> CGPoint {
                let envelope = pow(max(0, sin(.pi * t)), 0.85)
                let billow = 0.82 + 0.12 * sin(time + bend) + 0.06 * sin(time * 0.613 + bend * 2)
                let curl = 0.79 + 0.21 * sin(t * .pi * 2 + bend + time * 0.47)
                let outward = 4 + reach * reachScale * envelope * billow * curl
                let drift = 17 * envelope * sin(time * 0.73 + bend + t * .pi)
                return CGPoint(x: edge + side * outward, y: top + length * (1 - t) + drift)
            }
            var outside: [CGPoint] = []
            var inside: [CGPoint] = []
            for step in 0...56 {
                let t = Double(step) / 56
                let c = center(t)
                let previous = center(max(0, t - 0.005))
                let next = center(min(1, t + 0.005))
                let dx = next.x - previous.x
                let dy = next.y - previous.y
                let magnitude = max(0.001, hypot(dx, dy))
                let taper = pow(max(0, sin(.pi * t)), 1.4)
                let uneven = 0.76 + 0.24 * sin(t * .pi * 3 + bend + time * 0.39)
                let halfWidth = width * taper * uneven * 0.5
                let nx = -dy / magnitude * halfWidth
                let ny = dx / magnitude * halfWidth
                outside.append(CGPoint(x: c.x + nx, y: c.y + ny))
                inside.append(CGPoint(x: c.x - nx, y: c.y - ny))
            }
            var path = Path()
            path.addLines(outside + inside.reversed())
            path.closeSubpath()
            return path
        }
    }
}

private struct ExteriorCardMask: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        let inset = ShadowWispCanvas.margin - 3
        path.addRoundedRect(in: rect.insetBy(dx: inset, dy: inset), cornerSize: CGSize(width: 31, height: 31))
        return path
    }
}
